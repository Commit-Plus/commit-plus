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

final class ConflictAIResolutionTests: XCTestCase {
    func testResponseDecodesFencedStructuredPlan() throws {
        let response = try ConflictAIResolutionResponse.decode(from: """
            ```json
            {
              "decisions": [
                {
                  "sectionIndex": 1,
                  "action": "replace",
                  "replacementText": "merged()\\n",
                  "reason": "Combines both behaviors",
                  "question": "",
                  "options": []
                }
              ],
              "summary": "Merged the implementations"
            }
            ```
            """)

        XCTAssertEqual(response.decisions.count, 1)
        XCTAssertEqual(response.decisions[0].action, .replace)
        XCTAssertEqual(response.decisions[0].replacementText, "merged()\n")
    }

    func testPlanAppliesPresetAndReplacementDecisions() throws {
        let document = try ConflictResolutionDocument.parse("""
            before
            <<<<<<< HEAD
            current one
            =======
            incoming one
            >>>>>>> feature
            between
            <<<<<<< HEAD
            current two
            =======
            incoming two
            >>>>>>> feature
            after
            """)
        let indices = document.sections.indices.filter { document.sections[$0].isConflict }
        let response = ConflictAIResolutionResponse(decisions: [
            ConflictAIResolutionDecision(sectionIndex: indices[0], action: .incoming),
            ConflictAIResolutionDecision(
                sectionIndex: indices[1],
                action: .replace,
                replacementText: "merged two\n"
            ),
        ])

        let application = try ConflictAIResolutionPlanApplier.apply(
            response,
            to: document,
            filePath: "example.txt"
        )

        XCTAssertTrue(application.questions.isEmpty)
        XCTAssertTrue(application.document.resolvedText.contains("incoming one\n"))
        XCTAssertTrue(application.document.resolvedText.contains("merged two\n"))
        XCTAssertFalse(application.document.resolvedText.contains("current two\n"))
    }

    func testPlanRejectsMissingConflictDecision() throws {
        let document = try ConflictResolutionDocument.parse("""
            <<<<<<< HEAD
            current
            =======
            incoming
            >>>>>>> feature
            """)

        XCTAssertThrowsError(try ConflictAIResolutionPlanApplier.apply(
            ConflictAIResolutionResponse(decisions: []),
            to: document,
            filePath: "example.txt"
        )) { error in
            guard case ConflictAIResolutionError.incompletePlan = error else {
                return XCTFail("Expected incomplete plan, got \(error)")
            }
        }
    }

    func testNeedsUserDecisionCanApplySelectedOption() throws {
        let document = try ConflictResolutionDocument.parse("""
            <<<<<<< HEAD
            preserve API
            =======
            replace API
            >>>>>>> feature
            """)
        let sectionIndex = try XCTUnwrap(document.sections.firstIndex(where: \.isConflict))
        let response = ConflictAIResolutionResponse(decisions: [
            ConflictAIResolutionDecision(
                sectionIndex: sectionIndex,
                action: .needsUser,
                reason: "The intended public API is a product decision.",
                question: "Which public API should remain?",
                options: [
                    ConflictAIResolutionOption(label: "Preserve current API", action: .current),
                    ConflictAIResolutionOption(label: "Adopt incoming API", action: .incoming),
                ]
            ),
        ])
        var application = try ConflictAIResolutionPlanApplier.apply(
            response,
            to: document,
            filePath: "API.swift"
        )

        let question = try XCTUnwrap(application.questions.first)
        try ConflictAIResolutionPlanApplier.apply(
            question.options[1],
            to: &application.document,
            sectionIndex: question.sectionIndex,
            filePath: question.filePath
        )

        XCTAssertEqual(application.document.resolvedText, "replace API\n")
    }

    @MainActor
    func testControllerStagesCompletePlanWithoutUserReview() async throws {
        let loaded = try makeLoadedFile(path: "complete.txt", fingerprint: "fingerprint-1")
        let sectionIndex = try XCTUnwrap(loaded.document.sections.firstIndex(where: \.isConflict))
        let provider = StubConflictAIProvider(responses: [
            "complete.txt": ConflictAIResolutionResponse(decisions: [
                ConflictAIResolutionDecision(sectionIndex: sectionIndex, action: .bothCurrentFirst),
            ]),
        ])
        let fileService = StubConflictAIFileService(files: [loaded])
        let controller = makeController(provider: provider, fileService: fileService)

        let task = try XCTUnwrap(controller.start(files: [loaded.file]))
        await task.value

        XCTAssertEqual(controller.resolvedFilePaths, ["complete.txt"])
        XCTAssertTrue(controller.pendingQuestions.isEmpty)
        XCTAssertTrue(controller.failures.isEmpty)
        let appliedDocument = await fileService.appliedDocument(for: "complete.txt")
        XCTAssertEqual(appliedDocument?.resolvedText, "current\nincoming\n")
    }

    @MainActor
    func testControllerDefersOnlyNeedsUserPlanThenAppliesAnswer() async throws {
        let loaded = try makeLoadedFile(path: "question.txt", fingerprint: "fingerprint-2")
        let sectionIndex = try XCTUnwrap(loaded.document.sections.firstIndex(where: \.isConflict))
        let provider = StubConflictAIProvider(responses: [
            "question.txt": ConflictAIResolutionResponse(decisions: [
                ConflictAIResolutionDecision(
                    sectionIndex: sectionIndex,
                    action: .needsUser,
                    question: "Which behavior is intended?",
                    options: [
                        ConflictAIResolutionOption(label: "Current", action: .current),
                        ConflictAIResolutionOption(label: "Incoming", action: .incoming),
                    ]
                ),
            ]),
        ])
        let fileService = StubConflictAIFileService(files: [loaded])
        let controller = makeController(provider: provider, fileService: fileService)

        let task = try XCTUnwrap(controller.start(files: [loaded.file]))
        await task.value

        let question = try XCTUnwrap(controller.pendingQuestions.first)
        XCTAssertTrue(controller.resolvedFilePaths.isEmpty)
        let unappliedDocument = await fileService.appliedDocument(for: "question.txt")
        XCTAssertNil(unappliedDocument)

        controller.selectOption(at: 1, for: question)
        await controller.applySelectedAnswers()

        XCTAssertEqual(controller.resolvedFilePaths, ["question.txt"])
        XCTAssertTrue(controller.pendingQuestions.isEmpty)
        let appliedDocument = await fileService.appliedDocument(for: "question.txt")
        XCTAssertEqual(appliedDocument?.resolvedText, "incoming\n")
    }

    @MainActor
    private func makeController(
        provider: StubConflictAIProvider,
        fileService: StubConflictAIFileService
    ) -> ConflictAIResolutionController {
        let suiteName = "ConflictAIResolutionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let providerController = AIProviderController(
            registry: AIProviderRegistry(providers: [provider]),
            snapshotLoader: EmptyCommitSnapshotLoader(),
            defaults: defaults
        )
        return ConflictAIResolutionController(
            repositoryURL: URL(fileURLWithPath: "/tmp/example"),
            providerController: providerController,
            fileService: fileService
        )
    }

    private func makeLoadedFile(path: String, fingerprint: String) throws -> ConflictAILoadedFile {
        let workingText = """
            <<<<<<< HEAD
            current
            =======
            incoming
            >>>>>>> feature
            """
        let document = try ConflictResolutionDocument.parse(
            workingText,
            currentContent: "current\n",
            incomingContent: "incoming\n"
        )
        let sectionIndex = try XCTUnwrap(document.sections.firstIndex(where: \.isConflict))
        let file = StatusFile(path: path, status: .conflict, originalPath: nil)
        let snapshot = ConflictAIFileSnapshot(
            repositoryName: "example",
            branchName: "main",
            filePath: path,
            fingerprint: fingerprint,
            baseContent: "base\n",
            currentContent: "current\n",
            incomingContent: "incoming\n",
            sections: [ConflictAISectionSnapshot(
                sectionIndex: sectionIndex,
                contextBefore: "",
                currentText: "current\n",
                incomingText: "incoming\n",
                contextAfter: ""
            )],
            isTruncated: false
        )
        return ConflictAILoadedFile(
            file: file,
            document: document,
            snapshot: snapshot,
            originalWorkingTreeText: workingText
        )
    }
}

private struct StubConflictAIProvider: CommitMessageAIProvider {
    let descriptor = AIProviderDescriptor(
        id: .appleIntelligence,
        displayName: "Stub AI",
        systemImage: "sparkles",
        detail: "Test",
        dataProcessing: .onDevice,
        billing: .none,
        requiresProToConfigureAPIKey: false,
        defaultModel: nil,
        inputCharacterBudget: 7_000,
        isImplemented: true
    )
    let responses: [String: ConflictAIResolutionResponse]

    func availability() async -> AIProviderAvailability { .available }

    func generateCommitMessage(
        request: CommitMessageGenerationRequest
    ) async throws -> GeneratedCommitMessage {
        throw CommitMessageGenerationError.providerNotImplemented
    }

    func generateConflictResolution(
        request: ConflictAIResolutionRequest
    ) async throws -> ConflictAIResolutionResponse {
        guard let response = responses[request.snapshot.filePath] else {
            throw ConflictAIResolutionError.invalidResponse("Missing stub response")
        }
        return response
    }
}

private actor StubConflictAIFileService: ConflictAIFileServicing {
    private let files: [String: ConflictAILoadedFile]
    private var appliedDocuments: [String: ConflictResolutionDocument] = [:]

    init(files: [ConflictAILoadedFile]) {
        self.files = Dictionary(uniqueKeysWithValues: files.map { ($0.file.path, $0) })
    }

    func loadConflictAIFile(
        _ file: StatusFile,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> ConflictAILoadedFile {
        guard let loaded = files[file.path] else {
            throw ConflictAIResolutionError.unsupportedFile("Missing stub file")
        }
        return loaded
    }

    func conflictAIFingerprint(for file: StatusFile, in repositoryURL: URL) async throws -> String {
        guard let fingerprint = files[file.path]?.snapshot.fingerprint else {
            throw ConflictAIResolutionError.unsupportedFile("Missing stub fingerprint")
        }
        return fingerprint
    }

    func applyAIConflictResolution(
        file: StatusFile,
        document: ConflictResolutionDocument,
        expectedFingerprint: String,
        originalWorkingTreeText: String,
        in repositoryURL: URL
    ) async throws {
        guard files[file.path]?.snapshot.fingerprint == expectedFingerprint else {
            throw ConflictAIResolutionError.staleFile(file.path)
        }
        appliedDocuments[file.path] = document
    }

    func appliedDocument(for path: String) -> ConflictResolutionDocument? {
        appliedDocuments[path]
    }
}

private actor EmptyCommitSnapshotLoader: CommitChangeSnapshotLoading {
    func commitChangeSnapshot(
        in repositoryURL: URL,
        source: CommitChangeSource,
        characterBudget: Int
    ) async throws -> CommitChangeSnapshot {
        throw CommitMessageGenerationError.noChanges(source)
    }

    func changesFingerprint(
        in repositoryURL: URL,
        source: CommitChangeSource
    ) async throws -> String {
        ""
    }
}
