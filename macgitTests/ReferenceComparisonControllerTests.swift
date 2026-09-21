// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class ReferenceComparisonControllerTests: XCTestCase {
    func testSwapDiscardsLateFileListAndReloadsCommits() async {
        let gate = ComparisonTestGate()
        let service = ComparisonTestService(filesGate: gate)
        let controller = makeController(service)
        controller.reload()
        let oldTask = controller.loadTask
        await gate.waitForArrival()
        controller.swap()
        await controller.loadTask?.value
        await controller.baseCommitsTask?.value
        await controller.targetCommitsTask?.value
        XCTAssertEqual(controller.baseRef, "refs/heads/feature")
        XCTAssertEqual(controller.snapshot?.base, "refs/heads/feature")
        XCTAssertEqual(controller.files.first?.path, "refs/heads/feature.txt")
        XCTAssertEqual(controller.targetCommits.first?.hash, "refs/heads/main")
        await gate.open()
        await oldTask?.value
        XCTAssertEqual(controller.files.first?.path, "refs/heads/feature.txt")
        XCTAssertFalse(controller.isLoading)
    }

    func testChangingModeUsesSameSnapshotAndRejectsPreviousFiles() async {
        let gate = ComparisonTestGate()
        let service = ComparisonTestService(filesGate: gate)
        let controller = makeController(service)
        controller.reload()
        let oldTask = controller.loadTask
        await gate.waitForArrival()
        controller.setMode(.tips)
        await controller.loadTask?.value
        XCTAssertEqual(controller.files.first?.path, "tips.txt")
        await gate.open()
        await oldTask?.value
        XCTAssertEqual(controller.files.first?.path, "tips.txt")
        let calls = await service.snapshotCalls
        XCTAssertEqual(calls, 1)
    }

    func testChangingFileRejectsLatePatch() async throws {
        let gate = ComparisonTestGate()
        let service = ComparisonTestService(patchGate: gate)
        let controller = makeController(service)
        controller.reload()
        await controller.loadTask?.value
        let first = try XCTUnwrap(controller.files.first)
        let second = try XCTUnwrap(controller.files.last)
        controller.selectFile(first)
        let oldTask = controller.patchTask
        await gate.waitForArrival()
        controller.selectFile(second)
        await controller.patchTask?.value
        XCTAssertEqual(controller.patch?.isBinary, true)
        await gate.open()
        await oldTask?.value
        XCTAssertEqual(controller.selectedFile, second)
        XCTAssertEqual(controller.patch?.isBinary, true)
    }

    func testCancelRejectsLateResults() async {
        let gate = ComparisonTestGate()
        let controller = makeController(ComparisonTestService(filesGate: gate))
        controller.reload()
        let task = controller.loadTask
        await gate.waitForArrival()
        controller.cancel()
        await gate.open()
        await task?.value
        XCTAssertTrue(controller.isCancelled)
        XCTAssertFalse(controller.isLoading)
        XCTAssertTrue(controller.files.isEmpty)
        XCTAssertNil(controller.error)
    }

    func testFileErrorsDoNotBecomeEmptySuccess() async {
        let controller = makeController(ComparisonTestService(failFiles: true))
        controller.reload()
        await controller.loadTask?.value
        XCTAssertEqual(controller.error, "Unable to read files")
        XCTAssertFalse(controller.isLoading)
        XCTAssertNotNil(controller.snapshot)
    }

    func testDetachedHeadRequiresBaseSelectionAndTagModeDefaultsToTips() async {
        let service = ComparisonTestService()
        let detached = ReferenceComparisonController(repositoryURL: URL(fileURLWithPath: "/tmp/comparison"),
            baseRef: "", targetRef: "refs/heads/feature", service: service)
        detached.reload()
        await detached.loadTask?.value
        XCTAssertNil(detached.snapshot)
        XCTAssertFalse(detached.isLoading)
        let calls = await service.snapshotCalls
        XCTAssertEqual(calls, 0)
        detached.setBase("refs/heads/main")
        await detached.loadTask?.value
        XCTAssertNotNil(detached.snapshot)
        let tag = ReferenceComparisonController(repositoryURL: detached.repositoryURL,
            baseRef: "v1", targetRef: "HEAD", isBranchComparison: false, service: service)
        XCTAssertEqual(tag.mode, .tips)
    }

    func testSeparateRepositoriesDoNotShareComparisonState() async {
        let gate = ComparisonTestGate()
        let service = ComparisonTestService(filesGate: gate)
        let first = makeController(service)
        first.reload()
        let oldTask = first.loadTask
        await gate.waitForArrival()
        first.cancel()
        let second = ReferenceComparisonController(repositoryURL: URL(fileURLWithPath: "/tmp/other-repository"),
            baseRef: "refs/heads/feature", targetRef: "refs/heads/main", service: service)
        second.reload()
        await second.loadTask?.value
        await gate.open()
        await oldTask?.value
        XCTAssertTrue(first.files.isEmpty)
        XCTAssertEqual(second.files.first?.path, "refs/heads/feature.txt")
    }

    private func makeController(_ service: ComparisonTestService) -> ReferenceComparisonController {
        ReferenceComparisonController(repositoryURL: URL(fileURLWithPath: "/tmp/comparison"),
            baseRef: "refs/heads/main", targetRef: "refs/heads/feature", service: service)
    }
}

private actor ComparisonTestGate {
    private var arrived = false
    private var isOpen = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        if !isOpen {
            // Deliberately ignore cancellation to simulate a late service response.
            await withCheckedContinuation { releaseWaiter = $0 }
        }
    }

    func waitForArrival() async {
        if !arrived { await withCheckedContinuation { arrivalWaiter = $0 } }
    }

    func open() {
        isOpen = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor ComparisonTestService: ReferenceComparisonServing {
    let filesGate: ComparisonTestGate?
    let patchGate: ComparisonTestGate?
    let failFiles: Bool
    private(set) var snapshotCalls = 0

    init(filesGate: ComparisonTestGate? = nil, patchGate: ComparisonTestGate? = nil, failFiles: Bool = false) {
        self.filesGate = filesGate
        self.patchGate = patchGate
        self.failFiles = failFiles
    }

    func comparisonBranches(in repositoryURL: URL) async throws -> [ComparisonBranch] {
        [ComparisonBranch(ref: "refs/heads/main"), ComparisonBranch(ref: "refs/heads/feature")]
    }

    func comparisonSnapshot(base: String, target: String, branchesOnly: Bool, in repositoryURL: URL) async throws -> ReferenceComparisonSnapshot {
        snapshotCalls += 1
        return ReferenceComparisonSnapshot(base: base, target: target, mergeBases: ["ancestor"], baseOnlyCount: 1, targetOnlyCount: 1)
    }

    func comparisonFiles(snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> [CommitFileChange] {
        if failFiles { throw GitError.commandFailed("Unable to read files") }
        if snapshot.base == "refs/heads/main" && mode == .mergeBase { await filesGate?.wait() }
        return [CommitFileChange(path: mode == .tips ? "tips.txt" : "\(snapshot.base).txt", status: .modified),
                CommitFileChange(path: "binary.dat", status: .added)]
    }

    func comparisonCommits(snapshot: ReferenceComparisonSnapshot, targetSide: Bool, skip: Int, limit: Int, in repositoryURL: URL) async throws -> [Commit] {
        [Commit(hash: targetSide ? snapshot.target : snapshot.base, parents: [], message: "Commit", author: "Test", email: "test@example.com", date: .distantPast, refs: [])]
    }

    func comparisonPatch(file: CommitFileChange, snapshot: ReferenceComparisonSnapshot, mode: ReferenceComparisonMode, in repositoryURL: URL) async throws -> ReferenceComparisonPatch {
        if file.path != "binary.dat" { await patchGate?.wait() }
        return ReferenceComparisonPatch(hunks: [], isBinary: file.path == "binary.dat", isTruncated: false)
    }
}
