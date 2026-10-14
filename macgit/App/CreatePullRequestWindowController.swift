// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import SwiftUI

@MainActor
final class CreatePullRequestWindowController: NSWindowController, NSWindowDelegate, ObservableObject {
    private var onClose: (() -> Void)?
    @Published private(set) var cancelRequestID = UUID()

    init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show<Content: View>(repositoryName: String, content: Content, onClose: @escaping () -> Void) {
        close()
        self.onClose = onClose

        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let size = NSSize(
            width: min(1080, visibleFrame.width - 40),
            height: min(800, visibleFrame.height - 80)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Create Pull Request — \(repositoryName)"
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self

        let hostingView = NSHostingView(rootView: GeometryReader { geometry in
            content
                .frame(width: geometry.size.width, height: geometry.size.height)
        })
        // Window geometry owns the viewport, including the embedded split views.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        window.contentMinSize = NSSize(width: min(820, size.width), height: min(640, size.height))
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.midX - window.frame.width / 2,
            y: visibleFrame.midY - window.frame.height / 2
        ))
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    override func close() {
        window?.close()
    }

    func activateIfPresented() -> Bool {
        guard let window else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancelRequestID = UUID()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        let callback = onClose
        onClose = nil
        window = nil
        callback?()
    }
}

struct CreatePullRequestWindowContent: View {
    @ObservedObject var controller: PullRequestController
    @ObservedObject var windowController: CreatePullRequestWindowController
    let seed: PullRequestDraftSeed
    let repositoryURL: URL
    let authorizeAction: () async -> Bool
    let onGenerateText: PullRequestAIGenerationAction
    let onCancel: () -> Void
    let onCreate: (PullRequestDraft) async -> Void
    @State private var isSubmitting = false
    @State private var sourceBranchForChanges: String?
    @State private var targetBranchForChanges: String?

    var body: some View {
        CreatePullRequestView(
            seed: seed,
            repositoryURL: repositoryURL,
            isSubmitting: isSubmitting || controller.isPerformingAction,
            changedFileCount: controller.createDraftChangedFileCount,
            isLoadingChanges: controller.isLoadingCreateDraftChanges,
            changesErrorMessage: controller.createDraftChangesErrorMessage,
            participants: controller.createDraftParticipants,
            isLoadingParticipants: controller.isLoadingCreateDraftParticipants,
            participantsErrorMessage: controller.createDraftParticipantsErrorMessage,
            loadSourceBranches: { query in
                await controller.loadCreateDraftSourceBranches(query: query)
            },
            loadTargetBranches: { query in
                await controller.loadCreateDraftTargetBranches(query: query)
            },
            onGenerateText: onGenerateText,
            onCancel: onCancel,
            onBranchesChanged: { sourceBranch, targetBranch in
                sourceBranchForChanges = sourceBranch
                targetBranchForChanges = targetBranch
            },
            onCreate: { draft in
                guard !isSubmitting else { return }
                isSubmitting = true
                Task {
                    await onCreate(draft)
                    isSubmitting = false
                }
            },
            isPresentedInWindow: true,
            cancelRequestID: windowController.cancelRequestID
        )
        .task(id: [sourceBranchForChanges, targetBranchForChanges]) {
            guard let sourceBranch = sourceBranchForChanges else { return }
            guard await authorizeAction(), !Task.isCancelled else { return }
            if let targetBranch = targetBranchForChanges {
                await controller.loadCreateDraftChanges(sourceBranch: sourceBranch, targetBranch: targetBranch)
            } else {
                controller.resetCreateDraftChanges()
            }
        }
        .task {
            guard await authorizeAction(), !Task.isCancelled else { return }
            await controller.loadCreateDraftParticipants()
        }
        .overlay {
            if isSubmitting || controller.isPerformingAction {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(0.72)
                    ProgressView("Creating pull request…")
                        .controlSize(.large)
                }
                .ignoresSafeArea()
            }
        }
        .alert("Pull Request", isPresented: detailErrorPresented) {
            Button("OK", role: .cancel) {
                controller.detailErrorMessage = nil
            }
        } message: {
            Text(controller.detailErrorMessage ?? "Could not create pull request.")
        }
    }

    private var detailErrorPresented: Binding<Bool> {
        Binding(
            get: { controller.detailErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    controller.detailErrorMessage = nil
                }
            }
        )
    }
}
