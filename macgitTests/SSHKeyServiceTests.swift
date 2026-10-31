// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class SSHKeyServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgit-ssh-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".ssh", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    func testGenerateCreatesKeyPairListedWithFingerprint() async throws {
        let service = SSHKeyService(sshDirectory: directory)

        let privateKeyURL = try await service.generateKey(SSHKeyGenerationRequest(
            type: .ed25519, fileName: "work_key", comment: "dev@example.com", passphrase: ""
        ))

        XCTAssertEqual(privateKeyURL.lastPathComponent, "work_key")
        let permissions = try FileManager.default.attributesOfItem(atPath: privateKeyURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        let keys = await service.listKeys()
        XCTAssertEqual(keys.map(\.name), ["work_key"])
        XCTAssertEqual(keys.first?.keyType, "ssh-ed25519")
        XCTAssertTrue(keys.first?.publicKey.hasSuffix("dev@example.com") == true)
        XCTAssertTrue(keys.first?.fingerprint?.hasPrefix("SHA256:") == true)
    }

    func testGenerateRefusesToOverwriteExistingKey() async throws {
        let service = SSHKeyService(sshDirectory: directory)
        let request = SSHKeyGenerationRequest(type: .ed25519, fileName: "id_ed25519", comment: "", passphrase: "")
        _ = try await service.generateKey(request)

        do {
            _ = try await service.generateKey(request)
            XCTFail("Expected an existing key error")
        } catch {
            XCTAssertEqual(error as? SSHKeyServiceError, .keyAlreadyExists("id_ed25519"))
        }
    }

    func testListSkipsPublicKeysWithoutPrivateKey() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "ssh-ed25519 AAAA orphan".write(to: directory.appendingPathComponent("orphan.pub"), atomically: true, encoding: .utf8)
        try "Host *".write(to: directory.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let keys = await SSHKeyService(sshDirectory: directory).listKeys()

        XCTAssertTrue(keys.isEmpty)
    }

    func testFileNameValidation() {
        XCTAssertTrue(SSHKeyService.isValidFileName("id_ed25519"))
        XCTAssertFalse(SSHKeyService.isValidFileName(""))
        XCTAssertFalse(SSHKeyService.isValidFileName("../id"))
        XCTAssertFalse(SSHKeyService.isValidFileName(".hidden"))
        XCTAssertFalse(SSHKeyService.isValidFileName("key.pub"))
    }

    func testFingerprintParsing() {
        XCTAssertEqual(
            SSHKeyService.fingerprint(fromKeygenOutput: "256 SHA256:abcDEF123 dev@example.com (ED25519)\n"),
            "SHA256:abcDEF123"
        )
        XCTAssertNil(SSHKeyService.fingerprint(fromKeygenOutput: "not a key"))
    }
}
