// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum CopilotLanguageServerRuntimeError: LocalizedError, Equatable {
    case downloadFailed(String)
    case verificationFailed
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "The GitHub Copilot language server could not be downloaded: \(message) Try again."
        case .verificationFailed:
            return "The GitHub Copilot language server download failed security verification. Try again."
        case .installationFailed(let message):
            return "The GitHub Copilot language server could not be installed: \(message) Try again."
        }
    }
}

/// Downloads, verifies, and locates the pinned GitHub Copilot language server.
/// It reuses `GitRuntimeManager` with its own manifest and has no system option.
actor CopilotLanguageServerRuntime {
    static let shared = CopilotLanguageServerRuntime()

    private let manager: GitRuntimeManager
    private var installTask: Task<Void, Error>?

    init(manager: GitRuntimeManager? = nil) {
        self.manager = manager ?? GitRuntimeManager(
            configuration: Self.configuration(),
            processRunner: ProcessGitRuntimeRunner(),
            extractor: CopilotLanguageServerArchiveExtractor()
        )
    }

    nonisolated static func configuration(
        applicationSupportDirectory: URL = applicationSupportDirectory,
        preferenceDefaults: UserDefaults = .standard
    ) -> GitRuntimeConfiguration {
        GitRuntimeConfiguration(
            applicationSupportDirectory: applicationSupportDirectory,
            candidateSystemGitURLs: [],
            manifest: manifest,
            preferenceDefaults: preferenceDefaults,
            preferenceKey: "copilotLanguageServerRuntimePreference",
            managedDirectoryName: "GitHubCopilot/LanguageServer",
            executableRelativePath: "package/copilot-language-server",
            versionPrefix: manifest.version
        )
    }

    // Verified against the npm registry tarballs of
    // @github/copilot-language-server-darwin-{arm64,x64}@1.560.0.
    nonisolated static var manifest: GitRuntimeManifest {
        #if arch(arm64)
        let arch = "arm64"
        let size = 96_395_600
        let checksum = "f4a08df17fb007ee396ab173ba220c970ed304460328fc039835dd88ff8928c2"
        #else
        let arch = "x64"
        let size = 104_012_414
        let checksum = "dbf386b5d3ba5155924e329dcc11deb4c9edb470e6a0e47cd897660dcbe1f630"
        #endif
        let package = "copilot-language-server-darwin-\(arch)"
        return GitRuntimeManifest(
            version: "1.560.0",
            platform: "macos-\(arch)",
            url: URL(string: "https://registry.npmjs.org/@github/\(package)/-/\(package)-1.560.0.tgz")!,
            sha256: checksum,
            archiveSize: size
        )
    }

    /// Sign-in state lives here instead of the shared `~/.config/github-copilot`,
    /// so Commit+ never signs other Copilot clients in or out.
    nonisolated static var configHomeDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Commit+/GitHubCopilot/Config", isDirectory: true)
    }

    private nonisolated static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    func isInstalled() async -> Bool {
        await manager.status().embeddedRuntime != nil
    }

    /// Returns the cached server, downloading it first when it is missing.
    func executableURL() async throws -> URL {
        if let url = try? await manager.executableURL() {
            return url
        }
        try await install()
        do {
            return try await manager.executableURL()
        } catch {
            throw CopilotLanguageServerRuntimeError.installationFailed(error.localizedDescription)
        }
    }

    private func install() async throws {
        // Concurrent first uses share one download.
        if let installTask { return try await installTask.value }
        let task = Task { try await installRuntime() }
        installTask = task
        defer { installTask = nil }
        try await task.value
    }

    private func installRuntime() async throws {
        do {
            try await manager.installEmbeddedRuntime()
        } catch let error as GitRuntimeError {
            switch error {
            case .downloadFailed(let message):
                throw CopilotLanguageServerRuntimeError.downloadFailed(message)
            case .invalidArchiveSize, .checksumMismatch:
                throw CopilotLanguageServerRuntimeError.verificationFailed
            case .extractionFailed(let message):
                throw CopilotLanguageServerRuntimeError.installationFailed(message)
            case .validationFailed, .downloadInProgress, .missingSystemGit, .missingEmbeddedGit:
                throw CopilotLanguageServerRuntimeError.installationFailed(error.localizedDescription)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CopilotLanguageServerRuntimeError.installationFailed(error.localizedDescription)
        }
    }
}

nonisolated struct CopilotLanguageServerArchiveExtractor: GitRuntimeExtracting {
    nonisolated static func validateListing(_ listing: String) throws {
        let entries = listing.split(separator: "\n")
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..")
                && entry.hasPrefix("package/")
        }) else {
            throw GitRuntimeError.extractionFailed("The archive contains unsafe paths.")
        }
    }

    func extract(archiveURL: URL, to destinationURL: URL) throws {
        try Self.validateListing(try runTar(["-tzf", archiveURL.path]))
        let details = try runTar(["-tvzf", archiveURL.path])
        guard details.split(separator: "\n").allSatisfy({ $0.hasPrefix("-") || $0.hasPrefix("d") }) else {
            throw GitRuntimeError.extractionFailed("The archive contains unsupported links.")
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        _ = try runTar(["-xzf", archiveURL.path, "-C", destinationURL.path])
    }

    private func runTar(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitRuntimeError.extractionFailed("tar exited with status \(process.terminationStatus).")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
