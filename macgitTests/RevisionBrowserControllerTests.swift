// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
@testable import macgit

@MainActor
final class RevisionBrowserControllerTests: XCTestCase {
    func testLatePreviewCannotReplaceNewSelection() async throws {
        let service = BrowserTestService()
        let controller = RevisionBrowserController(repositoryURL: URL(fileURLWithPath: "/tmp/browser"), revision: "HEAD", service: service)
        controller.load()
        await controller.loadTask?.value
        let entries = try XCTUnwrap(controller.children[""])
        controller.select(entries[0])
        let oldTask = controller.previewTask
        await service.waitForArrival()
        controller.select(entries[1])
        XCTAssertNil(controller.preview)
        XCTAssertEqual(controller.selectedEntry, entries[1])
        await controller.previewTask?.value
        XCTAssertEqual(controller.preview?.text, "second")
        await service.release()
        await oldTask?.value
        XCTAssertEqual(controller.preview?.text, "second")
    }

    func testCancelRejectsLatePreview() async throws {
        let service = BrowserTestService()
        let controller = RevisionBrowserController(repositoryURL: URL(fileURLWithPath: "/tmp/browser"), revision: "HEAD", service: service)
        controller.load()
        await controller.loadTask?.value
        controller.select(try XCTUnwrap(controller.children[""]?.first))
        let task = controller.previewTask
        await service.waitForArrival()
        controller.cancel()
        await service.release()
        await task?.value
        XCTAssertNil(controller.preview)
        XCTAssertFalse(controller.isLoadingPreview)
        XCTAssertNil(controller.previewError)
    }

    func testTreeLoadsOnlyOnExpansionAndCachesChildren() async throws {
        let service = BrowserTestService()
        let controller = RevisionBrowserController(repositoryURL: URL(fileURLWithPath: "/tmp/browser"), revision: "HEAD", service: service)
        controller.load()
        await controller.loadTask?.value
        let initialCalls = await service.treeCalls
        XCTAssertEqual(initialCalls, [""])
        let folder = try XCTUnwrap(controller.children[""]?.last)
        controller.toggle(folder)
        await controller.folderTask(for: folder.path)?.value
        let calls = await service.treeCalls
        XCTAssertEqual(calls, ["", "folder"])
        XCTAssertTrue(controller.visibleEntries.contains { $0.path == "folder/child" })
        controller.toggle(folder)
        XCTAssertFalse(controller.visibleEntries.contains { $0.path == "folder/child" })
        controller.toggle(folder)
        let cachedCalls = await service.treeCalls
        XCTAssertEqual(cachedCalls, calls)
    }
}

private actor BrowserTestService: RevisionBrowserServing {
    private var arrived = false
    private var arrivalWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var treeCalls: [String] = []

    func browserSnapshot(revision: String, in repositoryURL: URL) async throws -> RevisionBrowserSnapshot {
        RevisionBrowserSnapshot(commitID: String(repeating: "a", count: 40), subject: "Snapshot")
    }

    func browserEntries(treeID: String, parentPath: String, in repositoryURL: URL) async throws -> [RevisionTreeEntry] {
        treeCalls.append(parentPath)
        if !parentPath.isEmpty { return [entry("folder/child")] }
        return [entry("first"), entry("second"), entry("folder", directory: true)]
    }

    func browserPreview(entry: RevisionTreeEntry, in repositoryURL: URL) async throws -> RevisionFilePreview {
        if entry.path == "first" {
            arrived = true
            arrivalWaiter?.resume()
            arrivalWaiter = nil
            // Simulate a service that finishes even after cancellation.
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return RevisionFilePreview(text: entry.path, lines: [], message: nil)
    }

    func waitForArrival() async {
        if !arrived { await withCheckedContinuation { arrivalWaiter = $0 } }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }

    private func entry(_ path: String, directory: Bool = false) -> RevisionTreeEntry {
        RevisionTreeEntry(path: path, objectID: String(repeating: "a", count: 40), mode: directory ? "040000" : "100644", objectType: directory ? "tree" : "blob", size: directory ? nil : 5)
    }
}
