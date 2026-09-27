// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class AIProviderAvailabilityTests: XCTestCase {
    func testInitializationDoesNotReadCredentials() async {
        let credentials = AvailabilityCredentialStore()
        let controller = makeController(registry: .live(credentialStore: credentials), credentials: credentials)
        XCTAssertEqual(credentials.readCount, 0)
        XCTAssertEqual(controller.selectedProviderAvailability, .checking)
        controller.invalidateAvailability()
        XCTAssertEqual(credentials.readCount, 0)
        await controller.refreshAvailability()
        XCTAssertGreaterThan(credentials.readCount, 0)
        XCTAssertTrue(controller.isAPIKeyConfigured(for: .openAI))
    }

    func testSelectedRefreshDoesNotCheckOtherProviders() async {
        let apple = AvailabilityProbe()
        let cloud = AvailabilityProbe()
        let controller = makeController(registry: AIProviderRegistry(providers: [
            AvailabilityTestProvider(id: .appleIntelligence, probe: apple),
            AvailabilityTestProvider(id: .openAI, probe: cloud),
        ]))
        await controller.refreshAvailability(selectedOnly: true)
        let appleCalls = await apple.calls
        let cloudCalls = await cloud.calls
        XCTAssertEqual(appleCalls, 1)
        XCTAssertEqual(cloudCalls, 0)
    }

    func testInvalidationRejectsSuspendedOldResult() async {
        let started = expectation(description: "Old availability read")
        let probe = AvailabilityProbe(started: { started.fulfill() })
        let controller = makeController(registry: AIProviderRegistry(providers: [
            AvailabilityTestProvider(id: .appleIntelligence, probe: probe)
        ]))
        let first = Task { await controller.refreshAvailability() }
        await fulfillment(of: [started], timeout: 2)
        controller.invalidateAvailability()
        await controller.refreshAvailability()
        XCTAssertEqual(controller.selectedProviderAvailability, .available)
        await probe.finishOldRead()
        await first.value
        XCTAssertEqual(controller.selectedProviderAvailability, .available)
        let calls = await probe.calls
        XCTAssertEqual(calls, 2)
    }

    private func makeController(
        registry: AIProviderRegistry,
        credentials: any AIProviderCredentialStore = AvailabilityCredentialStore()
    ) -> AIProviderController {
        let suite = "AIProviderAvailabilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AIProviderController(registry: registry, snapshotLoader: GitStatusService.shared,
                                    defaults: defaults, credentialStore: credentials)
    }
}

private actor AvailabilityProbe {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<AIProviderAvailability, Never>?
    private let started: (@Sendable () -> Void)?

    init(started: (@Sendable () -> Void)? = nil) { self.started = started }

    func read() async -> AIProviderAvailability {
        calls += 1
        if calls == 1, let started {
            return await withCheckedContinuation {
                continuation = $0
                started()
            }
        }
        return .available
    }

    func finishOldRead() {
        continuation?.resume(returning: .unavailable("Old account result"))
        continuation = nil
    }
}

private struct AvailabilityTestProvider: CommitMessageAIProvider {
    let descriptor: AIProviderDescriptor
    let probe: AvailabilityProbe

    init(id: AIProviderID, probe: AvailabilityProbe) {
        descriptor = AIProviderDescriptor(id: id, displayName: "Test", systemImage: "sparkles",
            detail: "Test", dataProcessing: .onDevice, billing: .none,
            requiresProToConfigureAPIKey: false, defaultModel: nil,
            inputCharacterBudget: 100, isImplemented: true)
        self.probe = probe
    }

    func availability() async -> AIProviderAvailability { await probe.read() }
    func generateCommitMessage(request: CommitMessageGenerationRequest) async throws -> GeneratedCommitMessage {
        GeneratedCommitMessage(subject: "Test", body: "")
    }
}

private final class AvailabilityCredentialStore: AIProviderCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var readCount: Int { lock.withLock { reads } }
    func apiKey(for providerID: AIProviderID) throws -> String? {
        lock.withLock { reads += 1 }
        return providerID == .openAI ? "test-key" : nil
    }
    func saveAPIKey(_ apiKey: String, for providerID: AIProviderID) throws {}
    func deleteAPIKey(for providerID: AIProviderID) throws {}
}
