//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

extension GitStatusService {
    func cloneRepository(
        remoteURL: String,
        to destinationURL: URL,
        checkoutBranch: String,
        recurseSubmodules: Bool,
        downloadLFSContent: Bool = true,
        credentialResolver: GitProviderCredentialResolver? = nil
    ) async throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        var arguments = ["clone"]

        let trimmedBranch = checkoutBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBranch.isEmpty {
            arguments += ["--branch", trimmedBranch]
        }

        if recurseSubmodules {
            arguments.append("--recurse-submodules")
        }

        arguments += ["--", remoteURL, destinationURL.path]
        let injection = try await credentialInjection(for: remoteURL, in: parentURL,
            credentialResolver: credentialResolver, credentialInjector: TemporaryGitCredentialInjector(),
            sshCredentialInjector: TemporaryGitSSHCredentialInjector())
        defer { injection?.cleanup() }
        var environment = injection?.environment ?? ProcessInfo.processInfo.environment
        environment["GIT_LFS_SKIP_SMUDGE"] = "1"
        // Clone Git data first so a failed LFS download never requires cloning again.
        _ = try await runGit(arguments: ["-c", "filter.lfs.process=", "-c", "filter.lfs.smudge=", "-c", "filter.lfs.required=false"] + arguments,
            in: parentURL, environment: environment)
        guard downloadLFSContent else { return }
        do {
            try await finishLFSClone(in: destinationURL, credentialResolver: credentialResolver)
        } catch {
            throw GitLFSCloneRecoveryError(repository: destinationURL, reason: error.localizedDescription)
        }
    }

    /// Finish both initial clone downloads and recovery, including initialized nested submodules.
    func finishLFSClone(in repository: URL, credentialResolver: GitProviderCredentialResolver? = nil) async throws {
        let submodulePaths = try await runGit(
            arguments: ["submodule", "foreach", "--quiet", "--recursive", #"printf '%s\0' "$PWD""#], in: repository)
        let repositories = [repository] + submodulePaths.split(separator: "\0").map { URL(fileURLWithPath: String($0)) }
        for checkout in repositories {
            try Task.checkCancellation()
            let files = try await runGit(arguments: ["ls-files", "-z"], in: checkout)
            let paths = files.split(separator: "\0").map(String.init)
            guard try await !lfsPaths(paths, in: checkout).isEmpty else { continue }
            // Fresh clones have one remote; respect clone.defaultRemoteName, including in submodules.
            let output = try await runGit(arguments: ["remote"], in: checkout)
            let remotes = output.split(whereSeparator: \.isNewline).map(String.init)
            guard let remote = remotes.count == 1 ? remotes.first : (remotes.contains("origin") ? "origin" : nil) else {
                throw GitError.commandFailed("Cannot determine the clone remote for \(checkout.lastPathComponent). Open Git LFS and select its remote.")
            }
            try await setupLFS(in: checkout)
            try await downloadLFS(remote: remote, in: checkout, credentialResolver: credentialResolver)
        }
    }

    func remoteBranches(remoteURL: String) async throws -> [String] {
        let output = try await runGit(
            arguments: ["ls-remote", "--heads", remoteURL],
            in: FileManager.default.temporaryDirectory
        )
        return Self.parseRemoteBranches(from: output)
    }

    static func parseRemoteBranches(from output: String) -> [String] {
        let branches = output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                guard let ref = line.split(separator: "\t").last else { return nil }
                let prefix = "refs/heads/"
                guard ref.hasPrefix(prefix) else { return nil }
                return String(ref.dropFirst(prefix.count))
            }

        return Array(Set(branches)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
