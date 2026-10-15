// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Observation

@MainActor @Observable
final class RepositoryDetailModel {
    private(set) var info: GitStatusService.RepositoryInfo?
    private(set) var readme: String?
    private(set) var readmeURL: URL?
    private(set) var size: Int64?
    private(set) var error: String?
    private(set) var isLoading = true
    private var currentURL: URL?

    func load(_ url: URL) async {
        if currentURL != url {
            info = nil; readme = nil; readmeURL = nil; size = nil; error = nil
            currentURL = url
        }
        isLoading = info == nil
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            error = "This repository is no longer available at its saved path."
            isLoading = false
            return
        }
        error = nil
        let readmeWorker = Task.detached(priority: .userInitiated) { try Self.readREADME(at: url) }
        async let metadata = GitStatusService.shared.repositoryInfo(in: url)
        do {
            let result = try await withTaskCancellationHandler { try await readmeWorker.value } onCancel: { readmeWorker.cancel() }
            guard !Task.isCancelled, currentURL == url else { return }
            if readme != result?.1 { readme = result?.1 }
            readmeURL = result?.0
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        let result = await metadata
        guard !Task.isCancelled, currentURL == url else { return }
        if info != result { info = result }
        isLoading = false
        let gitPath = try? await GitStatusService.shared.runGit(arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"], in: url)
        let gitURL = gitPath.map { URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true) }
        let worker = Task.detached(priority: .utility) { Self.repositorySize(at: url, gitDirectory: gitURL) }
        let bytes = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled, currentURL == url else { return }
        if size != bytes { size = bytes }
    }

    private nonisolated static func readREADME(at url: URL) throws -> (URL, String)? {
        let candidates = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { ["readme.md", "readme.markdown", "readme", "readme.txt"].contains($0.lastPathComponent.lowercased()) }
            .sorted {
                let order = ["readme.md", "readme.markdown", "readme", "readme.txt"]
                let a = order.firstIndex(of: $0.lastPathComponent.lowercased())!
                let b = order.firstIndex(of: $1.lastPathComponent.lowercased())!
                return a == b ? $0.lastPathComponent < $1.lastPathComponent : a < b
            }
        guard let file = candidates.first else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let limit = 512 * 1024
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        let content = String(decoding: data.prefix(limit), as: UTF8.self)
        return (file, content + (data.count > limit ? "\n\n*Preview truncated. Open the README to read the full file.*" : ""))
    }

    private nonisolated static func repositorySize(at url: URL, gitDirectory: URL?) -> Int64 {
        let worktree = url.standardizedFileURL.resolvingSymlinksInPath()
        var roots = [worktree]
        if let gitDirectory {
            let gitDirectory = gitDirectory.standardizedFileURL.resolvingSymlinksInPath()
            if gitDirectory != worktree && !gitDirectory.path.hasPrefix(worktree.path + "/") { roots.append(gitDirectory) }
        }
        var bytes: Int64 = 0
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            for case let file as URL in enumerator {
                if Task.isCancelled { return bytes }
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
            }
        }
        return bytes
    }
}
