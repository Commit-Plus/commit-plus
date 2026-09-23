// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import CryptoKit

actor GitLFSRuntime {
    static let shared = GitLFSRuntime()
    let manager: GitRuntimeManager
    private let commandDirectory: URL
    private var cachedURL: URL?
    private var didResolve = false
    private var commandPaths: [String: URL] = [:]

    init(manager: GitRuntimeManager? = nil, commandDirectory: URL? = nil) {
        self.commandDirectory = commandDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Commit+/GitLFS/CommandPaths")
        self.manager = manager ?? GitRuntimeManager(
            configuration: Self.configuration(), processRunner: GitLFSVersionRunner(), extractor: GitLFSArchiveExtractor()
        )
    }

    nonisolated static func configuration() -> GitRuntimeConfiguration {
        let candidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        return GitRuntimeConfiguration(
            applicationSupportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            candidateSystemGitURLs: candidates.map { URL(fileURLWithPath: $0).appendingPathComponent("git-lfs") },
            manifest: manifest, preferenceDefaults: .standard, preferenceKey: "gitLFSRuntimePreference",
            managedDirectoryName: "GitLFS", executableRelativePath: "git-lfs-3.8.0/git-lfs", versionPrefix: "git-lfs/"
        )
    }

    // Verified against the official git-lfs/git-lfs v3.8.0 release assets.
    nonisolated static var manifest: GitRuntimeManifest {
        #if arch(arm64)
        let arch = "arm64"
        let size = 5_550_634
        let checksum = "caff76a7d070d8160c89bc39b6e85d98f24135b6fed038a3b4de2590d25102d8"
        #else
        let arch = "amd64"
        let size = 6_198_060
        let checksum = "f1c17aeca0b4eaab9ea606226477dbed3b84b56fe0811a9f967d2ea2b2393c53"
        #endif
        return GitRuntimeManifest(version: "3.8.0", platform: "macos-\(arch)",
            url: URL(string: "https://github.com/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-darwin-\(arch)-v3.8.0.zip")!,
            sha256: checksum, archiveSize: size)
    }

    func status() async -> GitRuntimeStatus {
        let status = await manager.status()
        cachedURL = status.activeRuntime?.executableURL
        didResolve = true
        return status
    }

    func executable() async throws -> URL {
        if !didResolve { _ = await status() }
        guard let cachedURL, FileManager.default.isExecutableFile(atPath: cachedURL.path) else {
            throw GitError.commandFailed("Git LFS is unavailable. Open Git LFS to download Embedded Git LFS, or select System Git LFS in Settings.")
        }
        return cachedURL
    }

    func environment(inheriting environment: [String: String]) async throws -> [String: String] {
        if !didResolve { _ = await status() }
        var result = environment
        // Git prepends its exec-path ahead of PATH. Embedded Git includes its own
        // git-lfs, so PATH alone cannot enforce the user's separate LFS choice.
        if let corePath = environment["GIT_EXEC_PATH"] {
            let key = corePath + "|" + (cachedURL?.path ?? "missing")
            let commands: URL
            if let cached = commandPaths[key] { commands = cached }
            else {
                let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
                let root = commandDirectory
                commands = root.appendingPathComponent(digest)
                let staging = root.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: staging) }
                for source in try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: corePath), includingPropertiesForKeys: nil) where source.lastPathComponent != "git-lfs" {
                    try FileManager.default.createSymbolicLink(at: staging.appendingPathComponent(source.lastPathComponent), withDestinationURL: source)
                }
                let target = staging.appendingPathComponent("git-lfs")
                if let cachedURL {
                    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: cachedURL)
                } else {
                    try "#!/bin/sh\necho 'Git LFS is unavailable. Open Git LFS in Commit+ to install it.' >&2\nexit 127\n".write(to: target, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
                }
                if !FileManager.default.fileExists(atPath: commands.path) {
                    do { try FileManager.default.moveItem(at: staging, to: commands) }
                    catch { if !FileManager.default.fileExists(atPath: commands.path) { throw error } }
                }
                commandPaths[key] = commands
            }
            result["GIT_EXEC_PATH"] = commands.path
            result["PATH"] = commands.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        } else if let cachedURL {
            result["PATH"] = cachedURL.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        }
        return result
    }

    func select(_ preference: GitRuntimePreference) async throws {
        try await manager.setPreference(preference)
        _ = await status()
    }

    func install() async throws {
        try await manager.installEmbeddedRuntime()
        try Task.checkCancellation()
        try await select(.embedded)
    }
}
