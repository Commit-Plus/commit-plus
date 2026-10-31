// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class SSHKeysViewModel {
    private(set) var keys: [SSHKeyPair] = []
    private(set) var isLoading = false
    private(set) var isWorking = false
    var selectedKeyID: SSHKeyPair.ID?
    var errorMessage: String?
    var statusMessage: String?

    private let service: SSHKeyService

    init(service: SSHKeyService = SSHKeyService()) {
        self.service = service
    }

    var sshDirectoryPath: String { service.sshDirectory.path }

    var selectedKey: SSHKeyPair? {
        keys.first { $0.id == selectedKeyID }
    }

    func reload(selecting keyID: SSHKeyPair.ID? = nil) async {
        isLoading = true
        keys = await service.listKeys()
        isLoading = false
        if let keyID, keys.contains(where: { $0.id == keyID }) {
            selectedKeyID = keyID
        } else if selectedKey == nil {
            selectedKeyID = keys.first?.id
        }
    }

    /// Generates a key, then stores a passphrase in the Keychain so Git can use the key without a prompt.
    /// Returns whether the key was created.
    func generate(_ request: SSHKeyGenerationRequest) async -> Bool {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        statusMessage = nil

        let privateKeyURL: URL
        do {
            privateKeyURL = try await service.generateKey(request)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        await reload(selecting: privateKeyURL.path)
        if !request.passphrase.isEmpty {
            do {
                try await service.addToAgent(privateKeyURL: privateKeyURL, passphrase: request.passphrase)
            } catch {
                errorMessage = "The key was created, but its passphrase could not be saved to the Keychain: \(error.localizedDescription)"
                return true
            }
        }
        statusMessage = "Created \(privateKeyURL.lastPathComponent). Copy the public key to your Git provider."
        return true
    }

    func addSelectedKeyToKeychain(passphrase: String) async -> Bool {
        guard let key = selectedKey else { return false }
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        statusMessage = nil
        do {
            try await service.addToAgent(privateKeyURL: key.privateKeyURL, passphrase: passphrase)
            statusMessage = "Added \(key.name) to ssh-agent and the Keychain."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func copyPublicKey(_ key: SSHKeyPair) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(key.publicKey, forType: .string)
        statusMessage = "Copied the public key of \(key.name)."
    }

    func revealInFinder(_ key: SSHKeyPair) {
        NSWorkspace.shared.activateFileViewerSelecting([key.publicKeyURL])
    }

    func suggestedFileName(for type: SSHKeyType) -> String {
        let base = type.defaultFileName
        func isTaken(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: service.sshDirectory.appendingPathComponent(name).path)
        }
        guard isTaken(base) else { return base }
        var index = 2
        while isTaken("\(base)_\(index)") { index += 1 }
        return "\(base)_\(index)"
    }
}
