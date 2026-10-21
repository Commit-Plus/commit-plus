//
//  RepositoryOperationProgressTests.swift
//  macgitTests
//

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

@MainActor
final class RepositoryOperationProgressTests: XCTestCase {
    func testBeginAndEndTracksActiveOperation() {
        let progress = RepositoryOperationProgress()
        let id = progress.begin(message: "Fetching remotes...")

        XCTAssertEqual(progress.activeOperation?.id, id)
        XCTAssertEqual(progress.activeOperation?.message, "Fetching remotes...")
        XCTAssertEqual(progress.activeOperation?.canCancel, true)

        progress.end(id)

        XCTAssertNil(progress.activeOperation)
    }

    func testRunClearsOperationAfterCompletion() async {
        let progress = RepositoryOperationProgress()
        let operationRan = expectation(description: "operation ran")

        progress.run(message: "Pushing branches...") {
            operationRan.fulfill()
        }

        XCTAssertEqual(progress.activeOperation?.message, "Pushing branches...")

        await fulfillment(of: [operationRan], timeout: 1)
        await Task.yield()

        XCTAssertNil(progress.activeOperation)
    }

    func testInlineRunTracksActiveOperationWithoutOverlayOrCancel() async {
        let progress = RepositoryOperationProgress()
        let operationRan = expectation(description: "operation ran")

        progress.run(message: "Rebasing interactively...", showsOverlay: false) {
            operationRan.fulfill()
        }

        XCTAssertEqual(progress.activeOperation?.showsOverlay, false)
        XCTAssertEqual(progress.activeOperation?.canCancel, false)
        progress.cancelActiveOperation()
        XCTAssertEqual(progress.activeOperation?.isCancelling, false)

        await fulfillment(of: [operationRan], timeout: 1)
        await Task.yield()

        XCTAssertNil(progress.activeOperation)
    }

    func testCancelMarksOperationAndCancelsTask() async {
        let progress = RepositoryOperationProgress()
        let taskCancelled = expectation(description: "task cancelled")

        progress.run(message: "Pulling changes...") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            taskCancelled.fulfill()
        }

        progress.cancelActiveOperation()

        XCTAssertEqual(progress.activeOperation?.isCancelling, true)

        await fulfillment(of: [taskCancelled], timeout: 1)
        await Task.yield()

        XCTAssertNil(progress.activeOperation)
    }

    func testBackgroundItemsRunInOrderOneAtATime() async {
        let progress = RepositoryOperationProgress()
        var order: [String] = []
        var concurrent = 0
        var maxConcurrent = 0

        for title in ["Pushing", "Fetching", "Pushing tag"] {
            progress.runInBackground(title: title) {
                concurrent += 1
                maxConcurrent = max(maxConcurrent, concurrent)
                order.append(title)
                try? await Task.sleep(nanoseconds: 5_000_000)
                concurrent -= 1
                return .succeeded
            }
        }

        XCTAssertEqual(progress.backgroundItems.map(\.title), ["Pushing", "Fetching", "Pushing tag"])
        XCTAssertEqual(progress.backgroundIndicator, .running)
        XCTAssertNil(progress.activeOperation)

        await progress.waitForBackgroundIdle()

        XCTAssertEqual(order, ["Pushing", "Fetching", "Pushing tag"])
        XCTAssertEqual(maxConcurrent, 1)
        XCTAssertTrue(progress.backgroundItems.isEmpty)
        XCTAssertEqual(progress.backgroundIndicator, .idle)
        XCTAssertNil(progress.activeOperation)
    }

    func testQueuedItemWaitsWhileFirstItemRuns() async {
        let progress = RepositoryOperationProgress()
        let firstStarted = expectation(description: "first started")
        var releaseFirst: CheckedContinuation<Void, Never>?

        progress.runInBackground(title: "Pushing") {
            await withCheckedContinuation { continuation in
                releaseFirst = continuation
                firstStarted.fulfill()
            }
            return .succeeded
        }
        progress.runInBackground(title: "Fetching") { .succeeded }

        await fulfillment(of: [firstStarted], timeout: 1)

        XCTAssertEqual(progress.backgroundItems.map(\.state), [.running, .queued])

        releaseFirst?.resume()
        await progress.waitForBackgroundIdle()

        XCTAssertTrue(progress.backgroundItems.isEmpty)
    }

    func testFailedBackgroundItemIsRetainedUntilDismissed() async {
        let progress = RepositoryOperationProgress()
        let detail = "\n  ! [rejected] main -> main (non-fast-forward)\nhint: Updates were rejected"

        let id = progress.runInBackground(title: "Pushing branches") { .failed(detail) }
        await progress.waitForBackgroundIdle()

        XCTAssertEqual(progress.backgroundItems.count, 1)
        XCTAssertEqual(
            progress.backgroundItems.first?.state,
            .failed(summary: "! [rejected] main -> main (non-fast-forward)", detail: detail)
        )
        XCTAssertEqual(progress.backgroundIndicator, .failed)
        XCTAssertFalse(progress.hasPendingBackgroundWork)

        progress.dismissBackgroundItem(id: id)

        XCTAssertTrue(progress.backgroundItems.isEmpty)
        XCTAssertEqual(progress.backgroundIndicator, .idle)
    }

    func testRunningWinsOverFailedIndicator() async {
        let progress = RepositoryOperationProgress()
        progress.runInBackground(title: "Fetching") { .failed("network down") }
        await progress.waitForBackgroundIdle()

        progress.runInBackground(title: "Pushing") {
            try? await Task.sleep(nanoseconds: 5_000_000)
            return .succeeded
        }

        XCTAssertEqual(progress.backgroundIndicator, .running)

        await progress.waitForBackgroundIdle()

        XCTAssertEqual(progress.backgroundIndicator, .failed)
    }

    func testDismissIgnoresPendingItems() {
        let progress = RepositoryOperationProgress()
        let id = progress.runInBackground(title: "Fetching") {
            try? await Task.sleep(nanoseconds: 5_000_000)
            return .succeeded
        }

        progress.dismissBackgroundItem(id: id)

        XCTAssertEqual(progress.backgroundItems.map(\.id), [id])
        progress.cancelAllBackground()
    }

    func testWaitForBackgroundIdleReturnsImmediatelyWhenIdle() async {
        let progress = RepositoryOperationProgress()
        progress.runInBackground(title: "Fetching") { .failed("boom") }
        await progress.waitForBackgroundIdle()

        // A failed item does not count as pending work.
        await progress.waitForBackgroundIdle()

        XCTAssertEqual(progress.backgroundItems.count, 1)
    }

    func testWaitForBackgroundIdleStopsWaitingWhenCancelled() async {
        let progress = RepositoryOperationProgress()
        progress.runInBackground(title: "Pushing") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            return .succeeded
        }

        let waiter = Task { await progress.waitForBackgroundIdle() }
        try? await Task.sleep(nanoseconds: 5_000_000)
        waiter.cancel()
        await waiter.value

        XCTAssertTrue(progress.hasPendingBackgroundWork)
        progress.cancelAllBackground()
    }

    func testCancelAllBackgroundClearsItemsAndCancelsRunningWork() async {
        let progress = RepositoryOperationProgress()
        let workCancelled = expectation(description: "work cancelled")

        progress.runInBackground(title: "Pushing") {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
            workCancelled.fulfill()
            return .succeeded
        }
        progress.runInBackground(title: "Fetching") {
            XCTFail("Queued item must not run after cancel-all")
            return .succeeded
        }
        try? await Task.sleep(nanoseconds: 5_000_000)

        let waiter = Task { await progress.waitForBackgroundIdle() }
        progress.cancelAllBackground()

        await fulfillment(of: [workCancelled], timeout: 1)
        await waiter.value
        try? await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertTrue(progress.backgroundItems.isEmpty)
        XCTAssertEqual(progress.backgroundIndicator, .idle)
    }

    func testRunInBackgroundDropsOperationFromStaleGeneration() async {
        let progress = RepositoryOperationProgress()
        let staleGeneration = progress.backgroundGeneration
        progress.cancelAllBackground()

        let dropped = progress.runInBackground(ifGeneration: staleGeneration, title: "Pushing") {
            XCTFail("Operation queued before cancel-all must not run")
            return .succeeded
        }
        XCTAssertNil(dropped)
        XCTAssertTrue(progress.backgroundItems.isEmpty)

        let ran = expectation(description: "current generation runs")
        let queued = progress.runInBackground(ifGeneration: progress.backgroundGeneration, title: "Pushing") {
            ran.fulfill()
            return .succeeded
        }
        XCTAssertNotNil(queued)
        await fulfillment(of: [ran], timeout: 1)
    }

    func testQueuedItemWaitsForBeforeOperationHook() async {
        let progress = RepositoryOperationProgress()
        let hookEntered = expectation(description: "hook entered")
        var releaseHook: CheckedContinuation<Void, Never>?
        var didRun = false
        progress.waitBeforeBackgroundOperation = {
            guard releaseHook == nil else { return }
            await withCheckedContinuation { continuation in
                releaseHook = continuation
                hookEntered.fulfill()
            }
        }

        progress.runInBackground(title: "Fetching") {
            didRun = true
            return .succeeded
        }
        await fulfillment(of: [hookEntered], timeout: 1)

        XCTAssertFalse(didRun)
        XCTAssertEqual(progress.backgroundItems.map(\.state), [.queued])
        XCTAssertTrue(progress.hasPendingBackgroundWork)

        releaseHook?.resume()
        await progress.waitForBackgroundIdle()

        XCTAssertTrue(didRun)
        XCTAssertTrue(progress.backgroundItems.isEmpty)
    }

    func testBackgroundErrorSummaryUsesFirstLineAndTruncates() {
        XCTAssertEqual(RepositoryOperationProgress.backgroundErrorSummary("\n\n  fatal: bad\nmore"), "fatal: bad")
        XCTAssertEqual(RepositoryOperationProgress.backgroundErrorSummary("   \n"), "Unknown error")

        let long = String(repeating: "x", count: 200)
        let summary = RepositoryOperationProgress.backgroundErrorSummary(long)
        XCTAssertEqual(summary.count, 140)
        XCTAssertTrue(summary.hasSuffix("…"))
    }
}
