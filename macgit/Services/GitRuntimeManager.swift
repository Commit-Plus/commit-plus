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
import CryptoKit
import Foundation

protocol GitRuntimeProcessRunning: Sendable {
    func version(at executableURL: URL) async throws -> String
}

protocol GitRuntimeDownloading: Sendable {
    func download(from url: URL) async throws -> URL
}

protocol GitRuntimeExtracting: Sendable {
    func extract(archiveURL: URL, to destinationURL: URL) throws
}

struct GitRuntimeConfiguration: Sendable {
    let applicationSupportDirectory: URL
    let candidateSystemGitURLs: [URL]
    let manifest: GitRuntimeManifest
    let preferenceDefaults: UserDefaults
    let preferenceKey: String

    static func live() -> GitRuntimeConfiguration {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return GitRuntimeConfiguration(
            applicationSupportDirectory: supportDirectory,
            candidateSystemGitURLs: systemGitCandidateURLs(),
            manifest: .current,
            preferenceDefaults: .standard,
            preferenceKey: "gitRuntimePreference"
        )
    }

    private static func systemGitCandidateURLs() -> [URL] {
        let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("git") }
        let commonCandidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/git"),
            URL(fileURLWithPath: "/usr/local/bin/git"),
            URL(fileURLWithPath: "/opt/local/bin/git"),
            URL(fileURLWithPath: "/usr/local/git/bin/git"),
            URL(fileURLWithPath: "/usr/bin/git")
        ]

        var seenPaths = Set<String>()
        return (pathCandidates + commonCandidates).filter {
            seenPaths.insert($0.standardizedFileURL.path).inserted
        }
    }
}

actor GitRuntimeManager {
    static let shared = GitRuntimeManager()

    private let configuration: GitRuntimeConfiguration
    private let processRunner: any GitRuntimeProcessRunning
    private let downloader: any GitRuntimeDownloading
    private let extractor: any GitRuntimeExtracting
    private let fileManager: FileManager

    private var cachedActiveRuntime: GitRuntimeInstallation?
    private var isInstalling = false

    init(
        configuration: GitRuntimeConfiguration = .live(),
        processRunner: any GitRuntimeProcessRunning = ProcessGitRuntimeRunner(),
        downloader: any GitRuntimeDownloading = URLSessionGitRuntimeDownloader(),
        extractor: any GitRuntimeExtracting = TarGitRuntimeExtractor(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.processRunner = processRunner
        self.downloader = downloader
        self.extractor = extractor
        self.fileManager = fileManager
    }

    func status() async -> GitRuntimeStatus {
        async let systemRuntime = findSystemRuntime()
        async let embeddedRuntime = findEmbeddedRuntime()
        let runtimes = await (systemRuntime, embeddedRuntime)
        let preference = preference
        let activeRuntime = resolve(
            preference: preference,
            systemRuntime: runtimes.0,
            embeddedRuntime: runtimes.1
        )
        cachedActiveRuntime = activeRuntime

        return GitRuntimeStatus(
            preference: preference,
            activeRuntime: activeRuntime,
            systemRuntime: runtimes.0,
            embeddedRuntime: runtimes.1,
            embeddedVersion: configuration.manifest.version,
            embeddedDownloadSize: configuration.manifest.archiveSize
        )
    }

    func executableURL() async throws -> URL {
        if let cachedActiveRuntime,
           fileManager.isExecutableFile(atPath: cachedActiveRuntime.executableURL.path) {
            return cachedActiveRuntime.executableURL
        }
        cachedActiveRuntime = nil

        let currentStatus = await status()
        if let activeRuntime = currentStatus.activeRuntime {
            return activeRuntime.executableURL
        }

        switch currentStatus.preference {
        case .system:
            throw GitRuntimeError.missingSystemGit
        case .automatic, .embedded:
            throw GitRuntimeError.missingEmbeddedGit
        }
    }

    func environment(
        for executableURL: URL,
        inheriting baseEnvironment: [String: String]
    ) -> [String: String] {
        var environment = baseEnvironment
        // Finder-launched apps may not inherit package-manager paths. Git hooks
        // and filters need these to find external tools such as git-lfs.
        var paths = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .components(separatedBy: ":")
        for path in ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        where !paths.contains(path) {
            paths.append(path)
        }
        environment["PATH"] = paths.joined(separator: ":")

        guard executableURL == managedGitURL() else {
            return environment
        }

        let rootURL = managedRootURL()
        environment["GIT_EXEC_PATH"] = rootURL
            .appendingPathComponent("libexec/git-core", isDirectory: true)
            .path
        environment["GIT_CONFIG_SYSTEM"] = rootURL
            .appendingPathComponent("etc/gitconfig")
            .path
        environment["GIT_TEMPLATE_DIR"] = rootURL
            .appendingPathComponent("share/git-core/templates", isDirectory: true)
            .path

        let currentPath = environment["PATH"] ?? ""
        environment["PATH"] = [
            rootURL.appendingPathComponent("bin", isDirectory: true).path,
            rootURL.appendingPathComponent("libexec/git-core", isDirectory: true).path,
            currentPath
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ":")
        return environment
    }

    func setPreference(_ preference: GitRuntimePreference) async throws {
        let currentStatus = await status()

        switch preference {
        case .automatic:
            break
        case .system:
            guard currentStatus.systemRuntime != nil else {
                throw GitRuntimeError.missingSystemGit
            }
        case .embedded:
            guard currentStatus.embeddedRuntime != nil else {
                throw GitRuntimeError.missingEmbeddedGit
            }
        }

        configuration.preferenceDefaults.set(preference.rawValue, forKey: configuration.preferenceKey)
        cachedActiveRuntime = resolve(
            preference: preference,
            systemRuntime: currentStatus.systemRuntime,
            embeddedRuntime: currentStatus.embeddedRuntime
        )
    }

    func installEmbeddedRuntime() async throws {
        guard !isInstalling else {
            throw GitRuntimeError.downloadInProgress
        }
        isInstalling = true
        defer { isInstalling = false }

        let archiveURL: URL
        do {
            archiveURL = try await downloader.download(from: configuration.manifest.url)
        } catch let error as GitRuntimeError {
            throw error
        } catch {
            throw GitRuntimeError.downloadFailed(error.localizedDescription)
        }
        defer { try? fileManager.removeItem(at: archiveURL) }

        let archiveSize = (try? archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard archiveSize == configuration.manifest.archiveSize else {
            throw GitRuntimeError.invalidArchiveSize(
                expected: configuration.manifest.archiveSize,
                actual: archiveSize
            )
        }
        guard try sha256(of: archiveURL) == configuration.manifest.sha256 else {
            throw GitRuntimeError.checksumMismatch
        }

        let stagingURL = managedParentURL()
            .appendingPathComponent(".installing-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: stagingURL) }

        try extractor.extract(archiveURL: archiveURL, to: stagingURL)

        let stagedGitURL = gitURL(in: stagingURL)
        guard await validatedRuntime(at: stagedGitURL) != nil else {
            throw GitRuntimeError.validationFailed(stagedGitURL.path)
        }

        try promote(stagingURL: stagingURL, finalURL: managedRootURL())
        cachedActiveRuntime = nil
    }

    private var preference: GitRuntimePreference {
        guard let value = configuration.preferenceDefaults.string(
            forKey: configuration.preferenceKey
        ) else {
            return .automatic
        }
        return GitRuntimePreference(rawValue: value) ?? .automatic
    }

    private func findSystemRuntime() async -> GitRuntimeInstallation? {
        for url in configuration.candidateSystemGitURLs {
            if let runtime = await validatedRuntime(at: url) {
                return runtime
            }
        }
        return nil
    }

    private func findEmbeddedRuntime() async -> GitRuntimeInstallation? {
        await validatedRuntime(at: managedGitURL())
    }

    private func validatedRuntime(at url: URL) async -> GitRuntimeInstallation? {
        guard fileManager.isExecutableFile(atPath: url.path),
              let version = try? await processRunner.version(at: url),
              version.lowercased().contains("git version") else {
            return nil
        }
        return GitRuntimeInstallation(
            executableURL: url,
            version: version.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func resolve(
        preference: GitRuntimePreference,
        systemRuntime: GitRuntimeInstallation?,
        embeddedRuntime: GitRuntimeInstallation?
    ) -> GitRuntimeInstallation? {
        switch preference {
        case .automatic:
            return systemRuntime ?? embeddedRuntime
        case .system:
            return systemRuntime
        case .embedded:
            return embeddedRuntime
        }
    }

    private func managedParentURL() -> URL {
        configuration.applicationSupportDirectory
            .appendingPathComponent("Commit+", isDirectory: true)
            .appendingPathComponent("Git", isDirectory: true)
    }

    private func managedRootURL() -> URL {
        managedParentURL()
            .appendingPathComponent(
                "\(configuration.manifest.version)-\(configuration.manifest.platform)",
                isDirectory: true
            )
    }

    private func managedGitURL() -> URL {
        gitURL(in: managedRootURL())
    }

    private func gitURL(in rootURL: URL) -> URL {
        rootURL.appendingPathComponent("bin/git")
    }

    private func promote(stagingURL: URL, finalURL: URL) throws {
        let backupURL = managedParentURL()
            .appendingPathComponent(".replacing-\(UUID().uuidString)", isDirectory: true)
        var hasBackup = false

        do {
            try fileManager.createDirectory(
                at: managedParentURL(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.moveItem(at: finalURL, to: backupURL)
                hasBackup = true
            }

            try fileManager.moveItem(at: stagingURL, to: finalURL)
            if hasBackup {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if hasBackup {
                try? fileManager.removeItem(at: finalURL)
                try? fileManager.moveItem(at: backupURL, to: finalURL)
            }
            throw GitRuntimeError.extractionFailed(error.localizedDescription)
        }
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct ProcessGitRuntimeRunner: GitRuntimeProcessRunning {
    func version(at executableURL: URL) async throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--version"]

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitRuntimeError.validationFailed(executableURL.path)
        }

        guard process.terminationStatus == 0 else {
            throw GitRuntimeError.validationFailed(executableURL.path)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct URLSessionGitRuntimeDownloader: GitRuntimeDownloading {
    func download(from url: URL) async throws -> URL {
        do {
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw GitRuntimeError.downloadFailed("Unexpected server response.")
            }

            let retainedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("commitplus-embedded-git-\(UUID().uuidString).tar.gz")
            try FileManager.default.moveItem(at: temporaryURL, to: retainedURL)
            return retainedURL
        } catch let error as GitRuntimeError {
            throw error
        } catch {
            throw GitRuntimeError.downloadFailed(error.localizedDescription)
        }
    }
}

struct TarGitRuntimeExtractor: GitRuntimeExtracting {
    func extract(archiveURL: URL, to destinationURL: URL) throws {
        try FileManager.default.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archiveURL.path, "-C", destinationURL.path]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitRuntimeError.extractionFailed(error.localizedDescription)
        }

        guard process.terminationStatus == 0 else {
            throw GitRuntimeError.extractionFailed(
                "tar exited with status \(process.terminationStatus)."
            )
        }
    }
}
