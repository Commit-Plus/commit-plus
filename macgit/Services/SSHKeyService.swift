// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// An SSH key pair found in the user's SSH directory, identified by its private key file.
struct SSHKeyPair: Identifiable, Equatable, Hashable {
    var privateKeyURL: URL
    var publicKey: String
    var fingerprint: String?

    var id: String { privateKeyURL.path }
    var name: String { privateKeyURL.lastPathComponent }
    var publicKeyURL: URL { privateKeyURL.appendingPathExtension("pub") }

    /// The key algorithm, such as `ssh-ed25519`, taken from the public key line.
    var keyType: String? {
        publicKey.split(separator: " ", maxSplits: 1).first.map(String.init)
    }
}

enum SSHKeyType: String, CaseIterable, Identifiable {
    case ed25519
    case rsa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ed25519: "Ed25519 — Recommended"
        case .rsa: "RSA 4096"
        }
    }

    var defaultFileName: String {
        switch self {
        case .ed25519: "id_ed25519"
        case .rsa: "id_rsa"
        }
    }

    fileprivate var keygenArguments: [String] {
        switch self {
        case .ed25519: ["-t", "ed25519"]
        case .rsa: ["-t", "rsa", "-b", "4096"]
        }
    }
}

struct SSHKeyGenerationRequest: Equatable {
    var type: SSHKeyType
    var fileName: String
    var comment: String
    var passphrase: String
}

enum SSHKeyServiceError: LocalizedError, Equatable {
    case invalidFileName
    case keyAlreadyExists(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            "Enter a file name without slashes, such as id_ed25519."
        case .keyAlreadyExists(let name):
            "A key named \(name) already exists. Choose another file name."
        case .commandFailed(let message):
            message.isEmpty ? "The SSH command failed." : message
        }
    }
}

/// Lists and creates SSH keys with the system OpenSSH tools, the same keys `ssh` and Git use.
struct SSHKeyService {
    var sshDirectory: URL
    var fileManager: FileManager = .default

    static let systemSSHDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ssh", isDirectory: true)

    init(sshDirectory: URL = Self.systemSSHDirectory, fileManager: FileManager = .default) {
        self.sshDirectory = sshDirectory
        self.fileManager = fileManager
    }

    /// Key pairs whose private key and `.pub` file both exist, sorted by name.
    func listKeys() async -> [SSHKeyPair] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: sshDirectory.path) else { return [] }

        var keys: [SSHKeyPair] = []
        for name in names where name.hasSuffix(".pub") {
            let privateKeyURL = sshDirectory.appendingPathComponent(String(name.dropLast(4)), isDirectory: false)
            let publicKeyURL = sshDirectory.appendingPathComponent(name, isDirectory: false)
            guard fileManager.fileExists(atPath: privateKeyURL.path),
                  let publicKey = try? String(contentsOf: publicKeyURL, encoding: .utf8) else { continue }
            keys.append(SSHKeyPair(
                privateKeyURL: privateKeyURL,
                publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines),
                fingerprint: await fingerprint(of: publicKeyURL)
            ))
        }
        return keys.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The `SHA256:…` fingerprint, as GitHub and GitLab show it for uploaded keys.
    func fingerprint(of publicKeyURL: URL) async -> String? {
        guard let output = try? await Self.run("/usr/bin/ssh-keygen", ["-l", "-E", "sha256", "-f", publicKeyURL.path]) else {
            return nil
        }
        return Self.fingerprint(fromKeygenOutput: output)
    }

    /// Parses `256 SHA256:abc… comment (ED25519)` into `SHA256:abc…`.
    static func fingerprint(fromKeygenOutput output: String) -> String? {
        output.split(separator: " ").first { $0.hasPrefix("SHA256:") }.map(String.init)
    }

    func generateKey(_ request: SSHKeyGenerationRequest) async throws -> URL {
        let fileName = request.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidFileName(fileName) else { throw SSHKeyServiceError.invalidFileName }

        let privateKeyURL = sshDirectory.appendingPathComponent(fileName, isDirectory: false)
        guard !fileManager.fileExists(atPath: privateKeyURL.path),
              !fileManager.fileExists(atPath: privateKeyURL.path + ".pub") else {
            throw SSHKeyServiceError.keyAlreadyExists(fileName)
        }

        if !fileManager.fileExists(atPath: sshDirectory.path) {
            try fileManager.createDirectory(
                at: sshDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        try await Self.run(
            "/usr/bin/ssh-keygen",
            request.type.keygenArguments + [
                "-C", request.comment.trimmingCharacters(in: .whitespacesAndNewlines),
                "-N", request.passphrase,
                "-f", privateKeyURL.path,
                "-q"
            ]
        )
        return privateKeyURL
    }

    /// Loads the key into ssh-agent and stores its passphrase in the macOS Keychain, so Git can
    /// use a passphrase-protected key without a terminal prompt.
    func addToAgent(privateKeyURL: URL, passphrase: String) async throws {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("macgit-ssh-askpass-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fileManager.removeItem(at: directory) }

        let passphraseURL = directory.appendingPathComponent("passphrase", isDirectory: false)
        let helperURL = directory.appendingPathComponent("askpass", isDirectory: false)
        try passphrase.write(to: passphraseURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passphraseURL.path)
        try "#!/bin/sh\n/bin/cat \"$MACGIT_SSH_PASSPHRASE_FILE\"\n".write(to: helperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        try await Self.run(
            "/usr/bin/ssh-add",
            ["--apple-use-keychain", privateKeyURL.path],
            environment: [
                "SSH_ASKPASS": helperURL.path,
                "SSH_ASKPASS_REQUIRE": "force",
                "MACGIT_SSH_PASSPHRASE_FILE": passphraseURL.path
            ]
        )
    }

    static func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && !name.hasSuffix(".pub")
    }

    @discardableResult
    private static func run(
        _ executable: String,
        _ arguments: [String],
        environment overrides: [String: String] = [:]
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            // Without a terminal, SSH tools must never wait on an interactive prompt.
            environment["SSH_ASKPASS_REQUIRE"] = "never"
            task.environment = environment.merging(overrides) { _, new in new }
            task.standardInput = FileHandle.nullDevice

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe

            try task.run()
            let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            task.waitUntilExit()

            guard task.terminationStatus == 0 else {
                throw SSHKeyServiceError.commandFailed(error.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }
}
