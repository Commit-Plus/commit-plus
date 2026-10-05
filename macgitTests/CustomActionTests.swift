// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest
@testable import macgit

final class CustomActionTests: XCTestCase {
    func testDuplicatePreservesLocalOverrideAndEffectiveTrust() {
        for trusted in [false, true] {
            let suite = "CustomActionTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = CustomActionStore(userDefaults: defaults)
            let action = CustomActionDefinition(name: "Original", executablePath: "/remote/tool")
            store.upsert(action, trustOnThisMac: false)
            store.setExecutableOverride("/usr/bin/env", for: action)
            if trusted { store.trust(action) }

            // Callers may pass the effective action; its local path must never enter the catalog.
            store.duplicate(store.action(id: action.id)!)
            let copy = store.actions[1]
            XCTAssertNotEqual(copy.id, action.id)
            XCTAssertEqual(copy.executablePath, "/remote/tool")
            XCTAssertEqual(store.action(id: copy.id)?.executablePath, "/usr/bin/env")
            XCTAssertEqual(store.isTrusted(copy), trusted)

            let restored = CustomActionStore(userDefaults: defaults)
            XCTAssertEqual(restored.actions[1].executablePath, "/remote/tool")
            XCTAssertEqual(restored.action(id: copy.id)?.executablePath, "/usr/bin/env")
            XCTAssertEqual(restored.isTrusted(copy), trusted)
            restored.setExecutableOverride(nil, for: copy)
            XCTAssertFalse(restored.isTrusted(copy))
        }
    }

    func testUnrelatedEditPreservesLocalExecutableOverrideAndStoredPath() {
        let suite = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomActionStore(userDefaults: defaults)
        let action = CustomActionDefinition(name: "Original", executablePath: "/remote/tool")
        store.upsert(action, trustOnThisMac: false)
        store.setExecutableOverride("/usr/bin/env", for: action)
        let original = store.action(id: action.id)!
        var edited = original
        edited.name = "Renamed"
        edited.arguments = ["$REPO"]
        store.saveEditedAction(edited, original: original)
        XCTAssertEqual(store.actions[0].executablePath, "/remote/tool")
        XCTAssertEqual(store.action(id: action.id)?.executablePath, "/usr/bin/env")
        XCTAssertTrue(store.isTrusted(store.actions[0]))
        let restored = CustomActionStore(userDefaults: defaults)
        XCTAssertEqual(restored.actions[0].executablePath, "/remote/tool")
        XCTAssertEqual(restored.action(id: action.id)?.executablePath, "/usr/bin/env")

        var changedPath = store.action(id: action.id)!
        changedPath.executablePath = "/usr/bin/printf"
        store.saveEditedAction(changedPath, original: store.action(id: action.id))
        XCTAssertEqual(store.actions[0].executablePath, "/usr/bin/printf")
        XCTAssertEqual(store.action(id: action.id)?.executablePath, "/usr/bin/printf")
        XCTAssertTrue(store.isTrusted(store.actions[0]))
    }

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

    func testAccountCatalogsAndGuestActionsRemainSeparate() async {
        let suite = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomActionStore(userDefaults: defaults)
        let guest = CustomActionDefinition(name: "Guest", executablePath: "/usr/bin/env")
        let account = CustomActionDefinition(name: "Account", executablePath: "/usr/bin/env")
        store.upsert(guest)
        await store.updateCloudSession(uid: "A", enabled: false)
        XCTAssertTrue(store.actions.isEmpty)
        store.upsert(account)
        await store.updateCloudSession(uid: "B", enabled: false)
        XCTAssertTrue(store.actions.isEmpty)
        await store.updateCloudSession(uid: "A", enabled: false)
        XCTAssertEqual(store.actions, [account])
        await store.updateCloudSession(uid: nil, enabled: false)
        XCTAssertEqual(store.actions, [guest])
    }

    func testLocalEditDuringRemoteLoadSurvives() async {
        let suite = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = RecordingCustomActionCloudStore()
        let store = CustomActionStore(userDefaults: defaults, cloudStore: cloud)
        await store.updateCloudSession(uid: "A", enabled: true)
        let action = CustomActionDefinition(name: "New", executablePath: "/usr/bin/env")
        cloud.onLoad = { store.upsert(action) }
        await store.syncNow()
        XCTAssertEqual(store.actions, [action])
        cloud.onLoad = nil
        cloud.events = []
        await store.syncNow()
        XCTAssertEqual(cloud.events, ["upsert", "load"])
    }

    func testDuplicateDoesNotTrustUnreviewedAction() {
        let suite = "CustomActionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomActionStore(userDefaults: defaults)
        let action = CustomActionDefinition(name: "Unreviewed", executablePath: "/usr/bin/env")
        store.upsert(action, trustOnThisMac: false)
        store.duplicate(action)
        XCTAssertFalse(store.isTrusted(store.actions[1]))
    }

    func testQuotedLiteralBackslashesAndDollarArguments() throws {
        XCTAssertEqual(try CustomActionArgumentParser.parse(#""C:\path" "a\qb""#), [#"C:\path"#, #"a\qb"#])
        let action = CustomActionDefinition(name: "Literal", executablePath: "/usr/bin/env", arguments: ["price=$5", "--out=$HOME/file"])
        XCTAssertNoThrow(try CustomActionValidator.validate(action))
        XCTAssertEqual(try CustomActionArgumentParser.parse(CustomActionArgumentParser.joined(action.arguments)), action.arguments)
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

    func testValidatorRejectsPlaceholdersAtAnyArgumentPosition() {
        let cases: [(String, String)] = [
            ("$REPO/subdir", "$REPO"), ("$FILE,", "$FILE"), ("--x=$SHA^", "$SHA"),
            ("prefix/$REPO", "$REPO"), ("($FILE)", "$FILE"), ("prefix$SHA", "$SHA"),
            ("$HOME/$FILE", "$FILE"), ("$REPOSITORY/$REPO", "$REPO"),
            ("$REPO $FILE", "$REPO"), ("$SHA$SHA", "$SHA")
        ]
        for (argument, placeholder) in cases {
            let action = CustomActionDefinition(name: "Invalid", executablePath: "/usr/bin/env", arguments: [argument])
            XCTAssertThrowsError(try CustomActionValidator.validate(action), argument) { error in
                XCTAssertEqual(error as? CustomActionValidationError, .embeddedPlaceholder(placeholder), argument)
            }
        }
    }

    func testValidatorAllowsStandalonePlaceholdersAndLiteralDollarIdentifiers() {
        let arguments = [
            "$REPO", "$FILE", "$SHA", "$REPOSITORY", "$REPO_ROOT", "$FILE2", "$SHADOW",
            "$HOME/file", "price=$5", "prefix/$REPOSITORY", "$REPOé", "$REPO９"
        ]
        for argument in arguments {
            let action = CustomActionDefinition(name: "Valid", executablePath: "/usr/bin/env", arguments: [argument])
            XCTAssertNoThrow(try CustomActionValidator.validate(action), argument)
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
    var onLoad: (() -> Void)?
    private var actions: [CustomActionDefinition] = []

    func load(uid: String) async throws -> [CustomActionDefinition] {
        events.append("load")
        onLoad?()
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
