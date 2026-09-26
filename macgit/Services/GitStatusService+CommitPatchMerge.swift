// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

extension GitStatusService {
    func prepareCommitPatchReviewFile(file: CommitFileChange, patch: String, base: String,
                                     in repositoryURL: URL) async throws -> CommitPatchReviewFile {
        do {
            try await runCommitPatch(patch, checkOnly: true, reverse: false, in: repositoryURL)
            return CommitPatchReviewFile(file: file, patch: patch, state: .ready)
        } catch { try Task.checkCancellation() }

        // Check each file independently: a batch can contain both new and already-present changes.
        do {
            try await runCommitPatch(patch, checkOnly: true, reverse: true, in: repositoryURL)
            return CommitPatchReviewFile(file: file, patch: "", state: .alreadyApplied)
        } catch { try Task.checkCancellation() }

        let url = repositoryURL.appendingPathComponent(file.path)
        guard file.status == .modified, file.oldPath == nil,
              FileManager.default.fileExists(atPath: url.path),
              !patch.components(separatedBy: "\n").contains(where: { $0.hasPrefix("old mode ") || $0.hasPrefix("new mode ") }) else {
            return CommitPatchReviewFile(file: file, patch: patch, state: .conflict, conflict: .init(
                message: "This change adds, deletes, renames, or changes the permissions of a file whose current state is different. Commit+ will not overwrite it automatically. Skip this file to apply the others, or cancel and review its current state.",
                current: "", selected: "", markedResult: nil, permissions: 0))
        }
        let currentData = try Data(contentsOf: url)
        let baseData = try await showFile(at: file.path, ref: base, in: repositoryURL)
        guard let current = String(data: currentData, encoding: .utf8), !currentData.contains(0),
              String(data: baseData, encoding: .utf8) != nil, !baseData.contains(0),
              currentData.count <= 5_000_000, baseData.count <= 5_000_000 else {
            throw GitError.commandFailed("\(file.path) cannot be merged safely because its current or original content is binary, too large, or not UTF-8.")
        }
        let permissions = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o644
        let scratch = try await makeCommitPatchScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try writeCommitPatchScratchFile(baseData, path: file.path, permissions: permissions, in: scratch)
        let patchURL = scratch.appendingPathComponent(".git/selected.patch")
        try Data(patch.utf8).write(to: patchURL)
        // Materialize ONLY the selected patch against its true base, never the whole commit.
        _ = try await scratchGit(["apply", "--whitespace=nowarn", "--", patchURL.path], in: scratch)
        let selectedData = try Data(contentsOf: scratch.appendingPathComponent(file.path))
        guard let selected = String(data: selectedData, encoding: .utf8) else {
            throw GitError.commandFailed("Could not decode the selected changes in \(file.path).")
        }
        if currentData == selectedData {
            return CommitPatchReviewFile(file: file, patch: "", state: .alreadyApplied)
        }
        guard !CommitPatchReviewFile.containsConflictMarkers(current),
              !CommitPatchReviewFile.containsConflictMarkers(selected),
              !CommitPatchReviewFile.containsConflictMarkers(String(decoding: baseData, as: UTF8.self)) else {
            return CommitPatchReviewFile(file: file, patch: patch, state: .conflict, conflict: .init(
                message: "This file already contains conflict markers. Skip it or cancel and resolve those markers first.",
                current: current, selected: selected, markedResult: nil, permissions: permissions))
        }
        let oursURL = scratch.appendingPathComponent(".git/current")
        let baseURL = scratch.appendingPathComponent(".git/base")
        let selectedURL = scratch.appendingPathComponent(".git/selected")
        try currentData.write(to: oursURL)
        try baseData.write(to: baseURL)
        try selectedData.write(to: selectedURL)
        do {
            // merge-file writes only this scratch file, even when it returns conflicts.
            _ = try await scratchGit(["merge-file", "--no-diff3", "-L", "Your working copy",
                "-L", "Original", "-L", "Selected changes", oursURL.path, baseURL.path, selectedURL.path], in: scratch)
        } catch {
            try Task.checkCancellation()
            let marked = try String(contentsOf: oursURL, encoding: .utf8)
            let markerLines = marked.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .newlines) }
            guard markerLines.contains("<<<<<<< Your working copy"), markerLines.contains(">>>>>>> Selected changes") else { throw error }
            return CommitPatchReviewFile(file: file, patch: patch, state: .conflict, conflict: .init(
                message: "Your working copy and the selected changes edit the same lines. Resolve the result in a temporary preview; no files will be written until you click Apply.",
                current: current, selected: selected, markedResult: marked, permissions: permissions))
        }
        let merged = try String(contentsOf: oursURL, encoding: .utf8)
        if merged == current { return CommitPatchReviewFile(file: file, patch: "", state: .alreadyApplied) }
        let mergedPatch = try await commitPatchResultDiff(path: file.path, current: current,
            result: merged, permissions: permissions)
        try await runCommitPatch(mergedPatch, checkOnly: true, reverse: false, in: repositoryURL)
        return CommitPatchReviewFile(file: file, patch: mergedPatch, state: .merged)
    }

    /// A nil result explicitly skips the file. Neither resolving nor skipping mutates the real repository.
    func resolveCommitPatch(_ prepared: PreparedCommitPatch, fileID: UUID, result: String?) async throws -> PreparedCommitPatch {
        try await validateCommitPatchState(in: prepared.repositoryURL)
        guard try await commitPatchFingerprint(paths: prepared.paths, in: prepared.repositoryURL) == prepared.fingerprint else {
            throw GitError.commandFailed("Your working copy changed while reviewing. Cancel and select the changes again so nothing is overwritten.")
        }
        var updated = prepared
        guard let index = updated.reviewFiles.firstIndex(where: { $0.id == fileID }),
              let conflict = updated.reviewFiles[index].conflict, updated.reviewFiles[index].state == .conflict else {
            throw GitError.commandFailed("This file no longer needs resolution.")
        }
        if let result {
            guard conflict.markedResult != nil, !CommitPatchReviewFile.containsConflictMarkers(result), !result.utf8.contains(0),
                  result.utf8.count <= 5_000_000 else {
                throw GitError.commandFailed("Remove all conflict markers and review the result before continuing.")
            }
            let patch = try await commitPatchResultDiff(path: updated.reviewFiles[index].file.path,
                current: conflict.current, result: result, permissions: conflict.permissions)
            if !patch.isEmpty { try await runCommitPatch(patch, checkOnly: true, reverse: false, in: prepared.repositoryURL) }
            updated.reviewFiles[index].patch = patch
            updated.reviewFiles[index].state = .resolved
        } else {
            updated.reviewFiles[index].patch = ""
            updated.reviewFiles[index].state = .skipped
        }
        updated.reviewFiles[index].conflict = nil
        updated.rebuildPatch()
        return updated
    }

    private func commitPatchResultDiff(path: String, current: String, result: String, permissions: Int) async throws -> String {
        if current == result { return "" }
        let scratch = try await makeCommitPatchScratch()
        defer { try? FileManager.default.removeItem(at: scratch) }
        try writeCommitPatchScratchFile(Data(current.utf8), path: path, permissions: permissions, in: scratch)
        _ = try await scratchGit(["--literal-pathspecs", "add", "--force", "--", path], in: scratch)
        try writeCommitPatchScratchFile(Data(result.utf8), path: path, permissions: permissions, in: scratch)
        let data = try await scratchGit(["--literal-pathspecs", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
            "--no-relative", "--src-prefix=a/", "--dst-prefix=b/", "--full-index", "--", path], in: scratch)
        guard let patch = String(data: data, encoding: .utf8) else { throw GitError.commandFailed("Could not preview the merged result.") }
        return patch
    }

    private func makeCommitPatchScratch() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("commit-patch-merge-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            _ = try await scratchGit(["init", "--quiet", "--template="], in: url)
            let info = url.appendingPathComponent(".git/info")
            try FileManager.default.createDirectory(at: info, withIntermediateDirectories: true)
            // Do not run filters or normalize line endings from repository attributes in a scratch preview.
            try Data("* -text -filter -ident -working-tree-encoding diff\n".utf8).write(to: info.appendingPathComponent("attributes"))
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func writeCommitPatchScratchFile(_ data: Data, path: String, permissions: Int, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func scratchGit(_ arguments: [String], in directory: URL) async throws -> Data {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        return try await runGitRaw(arguments: ["-c", "core.autocrlf=false", "-c", "core.filemode=true"] + arguments,
            in: directory, environment: environment, outputByteLimit: 6_000_000)
    }
}
