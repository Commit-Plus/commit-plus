// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class CustomActionTests: XCTestCase {
    func testStorePersistsCatalogAndTrustSeparately() {
        let suiteName = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let action = CustomActionDefinition(name: "Environment", executablePath: "/usr/bin/env")

        let store = CustomActionStore(userDefaults: defaults)
        store.upsert(action)

        let restored = CustomActionStore(userDefaults: defaults)
        XCTAssertEqual(restored.actions, [action])
        XCTAssertTrue(restored.isTrusted(action))
    }

    func testStoreDefersCloudWriteUntilScheduledSync() async {
        let suiteName = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let cloudStore = RecordingCustomActionCloudStore()
        let store = CustomActionStore(userDefaults: defaults, cloudStore: cloudStore)
        await store.updateCloudSession(uid: "user", enabled: true)
        cloudStore.events = []

        let action = CustomActionDefinition(name: "Environment", executablePath: "/usr/bin/env")
        store.upsert(action)

        XCTAssertTrue(cloudStore.events.isEmpty)
        await store.syncNow()
        XCTAssertEqual(cloudStore.events, ["upsert", "load"])
    }

    func testArgumentParserPreservesQuotedArguments() throws {
        XCTAssertEqual(
            try CustomActionArgumentParser.parse(#"--flag "two words" 'three words' empty\ value"#),
            ["--flag", "two words", "three words", "empty value"]
        )
    }

    func testMultiValuePlaceholdersExpandAsSeparateArguments() {
        let context = CustomActionInvocationContext(
            repositoryURL: URL(fileURLWithPath: "/tmp/repo"),
            filePaths: ["one.swift", "folder/two.swift"],
            commitHashes: ["abc", "def"]
        )

        XCTAssertEqual(
            CustomActionArgumentExpander.expand(["$REPO", "$FILE", "--", "$SHA"], context: context),
            ["/tmp/repo", "one.swift", "folder/two.swift", "--", "abc", "def"]
        )
    }

    func testValidatorRejectsEmbeddedPlaceholder() {
        let action = CustomActionDefinition(
            name: "Invalid",
            executablePath: "/usr/bin/env",
            arguments: ["--repo=$REPO"]
        )

        XCTAssertThrowsError(try CustomActionValidator.validate(action)) { error in
            XCTAssertEqual(error as? CustomActionValidationError, .embeddedPlaceholder("$REPO"))
        }
    }

    func testAvailabilityRequiresSelectionAndLocalTrust() {
        let action = CustomActionDefinition(
            name: "Files",
            executablePath: "/usr/bin/env",
            arguments: ["$FILE"],
            availability: [.selectedFiles]
        )
        let context = CustomActionInvocationContext(
            repositoryURL: URL(fileURLWithPath: "/tmp/repo"),
            filePaths: [],
            commitHashes: []
        )

        XCTAssertNotNil(CustomActionValidator.unavailableReason(
            for: action,
            surface: .selectedFiles,
            context: context,
            isTrusted: false
        ))
        XCTAssertEqual(CustomActionValidator.unavailableReason(
            for: action,
            surface: .selectedFiles,
            context: context,
            isTrusted: true
        ), "Select one or more files first.")
    }

    func testExecutorCapturesProcessResult() async throws {
        let repositoryURL = FileManager.default.temporaryDirectory
        let action = CustomActionDefinition(
            name: "Print",
            executablePath: "/usr/bin/printf",
            arguments: ["%s", "$REPO"]
        )

        let result = await CustomActionExecutor().execute(
            action: action,
            context: CustomActionInvocationContext(
                repositoryURL: repositoryURL,
                filePaths: [],
                commitHashes: []
            )
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput, repositoryURL.path)
    }

    func testExecutorCancellationTerminatesProcess() async throws {
        let action = CustomActionDefinition(
            name: "Sleep",
            executablePath: "/bin/sleep",
            arguments: ["5"]
        )
        let executor = CustomActionExecutor()
        let task = Task {
            await executor.execute(
                action: action,
                context: CustomActionInvocationContext(
                    repositoryURL: FileManager.default.temporaryDirectory,
                    filePaths: [],
                    commitHashes: []
                )
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result.status, .cancelled)
    }
}

@MainActor
private final class RecordingCustomActionCloudStore: CustomActionCloudStore {
    var events: [String] = []
    private var actions: [CustomActionDefinition] = []

    func load(uid: String) async throws -> [CustomActionDefinition] {
        events.append("load")
        return actions
    }

    func upsert(_ action: CustomActionDefinition, uid: String) async throws {
        events.append("upsert")
        actions.removeAll { $0.id == action.id }
        actions.append(action)
    }

    func delete(id: UUID, uid: String) async throws {
        events.append("delete")
        actions.removeAll { $0.id == id }
    }

    func updateOrder(_ actions: [CustomActionDefinition], uid: String) async throws {
        events.append("order")
        self.actions = actions
    }
}
