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
import XCTest
@testable import macgit

final class AICommitMessageTests: XCTestCase {
    func testAppleRepositoryGitArgumentsDropOneExecutablePrefix() {
        XCTAssertEqual(
            AppleIntelligenceCommitMessageProvider.normalizedRepositoryGitArguments([
                "git", "diff", "--cached"
            ]),
            ["diff", "--cached"]
        )
        XCTAssertEqual(
            AppleIntelligenceCommitMessageProvider.normalizedRepositoryGitArguments([
                " Git ", "status", "--short"
            ]),
            ["status", "--short"]
        )
    }

    func testAppleRepositoryGitArgumentsKeepValidInputAndDropOnlyOnePrefix() {
        XCTAssertEqual(
            AppleIntelligenceCommitMessageProvider.normalizedRepositoryGitArguments([
                "diff", "--cached"
            ]),
            ["diff", "--cached"]
        )
        XCTAssertEqual(
            AppleIntelligenceCommitMessageProvider.normalizedRepositoryGitArguments([
                "git", "git", "status"
            ]),
            ["git", "status"]
        )
    }

    func testContextBuilderBoundsLargePatch() {
        let patch = String(repeating: "+let generated = true\n", count: 500)

        let result = CommitMessageContextBuilder.build(
            nameStatus: "M\tmacgit/App.swift",
            numberStats: "500\t0\tmacgit/App.swift",
            patch: patch,
            characterBudget: 2_500
        )

        XCTAssertTrue(result.isTruncated)
        XCTAssertTrue(result.context.contains("M\tmacgit/App.swift"))
        XCTAssertTrue(result.context.contains("[Additional change data omitted]"))
        XCTAssertLessThan(result.context.count, patch.count)
    }

    func testContextBuilderPreservesSmallPatch() {
        let result = CommitMessageContextBuilder.build(
            nameStatus: "M\tREADME.md",
            numberStats: "1\t1\tREADME.md",
            patch: "@@ -1 +1 @@\n-old\n+new",
            characterBudget: 7_000
        )

        XCTAssertFalse(result.isTruncated)
        XCTAssertTrue(result.context.contains("-old\n+new"))
    }

    func testConventionalFormatterAddsTypeAndDropsDuplicateBody() throws {
        let result = try ConventionalCommitMessageFormatter.format(
            type: "feat",
            subject: "Add pricing page and plan comparison.",
            body: "Add pricing page and plan comparison"
        )

        XCTAssertEqual(result.subject, "feat: Add pricing page and plan comparison")
        XCTAssertNil(result.body)
        XCTAssertEqual(result.text, "feat: Add pricing page and plan comparison")
    }

    func testConventionalFormatterAvoidsDuplicateTypeAndKeepsDistinctBody() throws {
        let result = try ConventionalCommitMessageFormatter.format(
            type: "fix",
            subject: "feat(pricing): Replace pricing for Pro plan",
            body: "Use the annual Pro amount in the plan card and comparison table."
        )

        XCTAssertEqual(result.subject, "fix: Replace pricing for Pro plan")
        XCTAssertEqual(
            result.body,
            "Use the annual Pro amount in the plan card and comparison table."
        )
    }

    @MainActor
    func testLiveRegistryProvidesCredentialBackedCloudProviders() async {
        let credentialStore = InMemoryAIProviderCredentialStore()
        let registry = AIProviderRegistry.live(credentialStore: credentialStore)
        let ids = registry.descriptors.map(\.id)

        XCTAssertEqual(
            ids,
            [.appleIntelligence, .openAI, .googleGemini, .anthropic, .deepSeek, .openRouter]
        )
        XCTAssertEqual(registry.provider(for: .appleIntelligence)?.descriptor.billing, AIProviderBilling.none)
        for id in [AIProviderID.openAI, .anthropic, .googleGemini, .deepSeek, .openRouter] {
            let provider = registry.provider(for: id)
            let availability = await provider?.availability()
            XCTAssertEqual(availability, .unavailable("Add an API key in Settings → AI Providers."))
            XCTAssertEqual(provider?.descriptor.isImplemented, true)
            XCTAssertEqual(provider?.descriptor.billing, .bringYourOwnKey)
            XCTAssertFalse(provider?.descriptor.billing.requiresProAccess ?? true)
        }
        XCTAssertFalse(registry.provider(for: .openAI)?.descriptor.requiresProToConfigureAPIKey ?? true)
        XCTAssertFalse(registry.provider(for: .googleGemini)?.descriptor.requiresProToConfigureAPIKey ?? true)
        XCTAssertTrue(registry.provider(for: .anthropic)?.descriptor.requiresProToConfigureAPIKey ?? false)
        XCTAssertTrue(registry.provider(for: .deepSeek)?.descriptor.requiresProToConfigureAPIKey ?? false)
        XCTAssertTrue(registry.provider(for: .openRouter)?.descriptor.requiresProToConfigureAPIKey ?? false)
    }

    func testOnlyCommitPlusFundedProvidersRequireProAccess() {
        XCTAssertFalse(AIProviderBilling.none.requiresProAccess)
        XCTAssertFalse(AIProviderBilling.bringYourOwnKey.requiresProAccess)
        XCTAssertTrue(AIProviderBilling.commitPlus.requiresProAccess)
    }

    @MainActor
    func testControllerDefaultsToAppleAndGeneratesThroughProviderSeam() async throws {
        let defaults = makeDefaults()
        let provider = StubCommitMessageProvider()
        let loader = StubCommitChangeSnapshotLoader(currentFingerprint: "tree-1")
        let controller = AIProviderController(
            registry: AIProviderRegistry(providers: [provider]),
            snapshotLoader: loader,
            defaults: defaults
        )

        await controller.refreshAvailability()
        let result = try await controller.generateCommitMessage(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            branchName: "main",
            changeSource: .staged,
            recentCommitSubjects: ["Improve status loading"]
        )

        XCTAssertEqual(controller.selectedProviderID, .appleIntelligence)
        XCTAssertEqual(controller.selectedProviderAvailability, .available)
        XCTAssertEqual(result.text, "Generate commit message\n\nUse the provider seam")
        let receivedCharacterBudget = await loader.receivedCharacterBudget()
        XCTAssertEqual(receivedCharacterBudget, 7_000)
        let receivedSource = await loader.receivedSource()
        XCTAssertEqual(receivedSource, .staged)
    }

    @MainActor
    func testControllerRejectsResponseWhenStagedTreeChanges() async throws {
        let defaults = makeDefaults()
        let loader = StubCommitChangeSnapshotLoader(currentFingerprint: "tree-2")
        let controller = AIProviderController(
            registry: AIProviderRegistry(providers: [StubCommitMessageProvider()]),
            snapshotLoader: loader,
            defaults: defaults
        )

        do {
            _ = try await controller.generateCommitMessage(
                repositoryURL: URL(fileURLWithPath: "/tmp/example"),
                branchName: "main",
                changeSource: .workingTree,
                recentCommitSubjects: []
            )
            XCTFail("Expected staged-change validation to reject the response")
        } catch let error as CommitMessageGenerationError {
            XCTAssertEqual(error, .changesChanged(.workingTree))
        }
    }

    @MainActor
    private func makeDefaults() -> UserDefaults {
        let suiteName = "AICommitMessageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct StubCommitMessageProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .appleIntelligence,
        displayName: "Apple Intelligence",
        systemImage: "sparkles",
        detail: "On-device",
        dataProcessing: .onDevice,
        billing: .none,
        requiresProToConfigureAPIKey: false,
        defaultModel: nil,
        inputCharacterBudget: 7_000,
        isImplemented: true
    )

    func availability() async -> AIProviderAvailability {
        .available
    }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        XCTAssertEqual(request.branchName, "main")
        return GeneratedCommitMessage(
            subject: "Generate commit message",
            body: "Use the provider seam"
        )
    }
}

private actor StubCommitChangeSnapshotLoader: CommitChangeSnapshotLoading {
    private let currentFingerprint: String
    private var characterBudget: Int?
    private var source: CommitChangeSource?

    init(currentFingerprint: String) {
        self.currentFingerprint = currentFingerprint
    }

    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        self.characterBudget = characterBudget
        self.source = source
        return CommitChangeSnapshot(
            fingerprint: "tree-1",
            context: "M\tmacgit/App.swift\n+new behavior",
            isTruncated: false
        )
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        currentFingerprint
    }

    func receivedCharacterBudget() -> Int? {
        characterBudget
    }

    func receivedSource() -> CommitChangeSource? {
        source
    }
}
