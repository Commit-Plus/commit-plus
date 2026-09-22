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

import SwiftUI

struct RepositoryAIChatTranscriptView: View {
    private static let pageSize = 20
    private static let bottomID = "conversation-bottom"

    @ObservedObject var controller: RepositoryAIChatController
    @State private var firstMessageIndex: Int
    @State private var followsStreaming = true
    @State private var showsScrollIndicator = false
    @State private var scrollHideTask: Task<Void, Never>?

    init(controller: RepositoryAIChatController) {
        self.controller = controller
        _firstMessageIndex = State(initialValue: max(0, controller.messages.count - Self.pageSize))
    }

    private var visibleMessages: ArraySlice<RepositoryAIMessage> {
        controller.messages.dropFirst(firstMessageIndex)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Measure the loaded messages exactly: lazy height estimates are unreliable
                // for long Markdown responses and can misplace the scrollbar thumb.
                VStack(alignment: .leading, spacing: 12) {
                    if firstMessageIndex > 0 {
                        Button("Load older messages (\(firstMessageIndex) remaining)") {
                            followsStreaming = false
                            firstMessageIndex = max(0, firstMessageIndex - Self.pageSize)
                        }
                        .buttonStyle(.bordered)
                        .pointingHandCursor()
                        .frame(maxWidth: .infinity)
                    }

                    ForEach(visibleMessages) { message in
                        RepositoryAIMessageView(message: message)
                            .id(message.id)
                    }

                    if controller.isRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.trailing, 8)
                .background {
                    ScrollViewIndicatorController(
                        showsIndicators: showsScrollIndicator,
                        controlSize: .small,
                        onScroll: { }
                    )
                }
            }
            // Recreated for each history selection, including selecting the same chat again.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onChange(of: firstMessageIndex) { previousIndex, _ in
                guard controller.messages.indices.contains(previousIndex) else { return }
                // Keep the previous first message at the top after prepending a page.
                proxy.scrollTo(controller.messages[previousIndex].id, anchor: .top)
            }
            .onChange(of: controller.messages.count) {
                guard followsStreaming else { return }
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onChange(of: controller.streamingRevision) {
                guard followsStreaming, controller.isRunning else { return }
                proxy.scrollTo(Self.bottomID, anchor: .bottom)
            }
            .onScrollPhaseChange { _, newPhase, context in
                switch newPhase {
                case .tracking, .interacting:
                    scrollHideTask?.cancel()
                    showsScrollIndicator = true
                    followsStreaming = false
                case .idle:
                    hideScrollIndicatorAfterDelay()
                    followsStreaming = context.geometry.visibleRect.maxY
                        >= context.geometry.contentSize.height - 24
                case .decelerating, .animating:
                    break
                @unknown default:
                    break
                }
            }
            .onDisappear {
                scrollHideTask?.cancel()
                scrollHideTask = nil
                showsScrollIndicator = false
            }
        }
    }

    private func hideScrollIndicatorAfterDelay() {
        scrollHideTask?.cancel()
        scrollHideTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
            showsScrollIndicator = false
        }
    }
}
