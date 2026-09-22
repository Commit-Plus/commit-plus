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

struct RepositoryAIChatHistorySheet: View {
    @ObservedObject var controller: RepositoryAIChatController
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var conversations: [RepositoryAIConversationSummary] = []
    @State private var isLoading = true
    @State private var isOpening = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var isReady = false
    @State private var conversationPendingDeletion: RepositoryAIConversationSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conversation History").font(.title2.bold())
                    Text("Saved chats for this repository").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .pointingHandCursor()
                    .keyboardShortcut(.cancelAction)
            }
            TextField("Search titles and messages", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search conversation history")
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).textSelection(.enabled)
            }
            Group {
                if isLoading {
                    ProgressView()
                } else if conversations.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "No saved conversations" : "No matching conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text(search.isEmpty ? "Your chats are saved automatically on this Mac." : "Try another title or phrase.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(conversations) { conversation in
                                HStack(spacing: 8) {
                                    Button { open(conversation) } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(conversation.title).font(.headline).lineLimit(1)
                                                Spacer()
                                                Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Text(conversation.preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .pointingHandCursor()
                                    .disabled(isOpening || isDeleting || controller.isInteractionDisabled)

                                    Button("Delete conversation", systemImage: "trash") {
                                        conversationPendingDeletion = conversation
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                    .pointingHandCursor()
                                    .foregroundStyle(.red)
                                    .help("Delete conversation")
                                    .disabled(isOpening || isDeleting || controller.isInteractionDisabled)
                                    .confirmationDialog(
                                        "Delete \(conversation.title)?",
                                        isPresented: Binding(
                                            get: { conversationPendingDeletion?.id == conversation.id },
                                            set: { if !$0 { conversationPendingDeletion = nil } }
                                        ),
                                        titleVisibility: .visible
                                    ) {
                                        Button("Delete", role: .destructive) {
                                            delete(conversation)
                                        }
                                    } message: {
                                        Text("This conversation will be permanently deleted.")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isOpening { ProgressView("Opening conversation…") }
        }
        .padding(24)
        .frame(width: 620, height: 480, alignment: .topLeading)
        .task {
            await controller.prepareConversationHistory()
            isReady = true
        }
        .task(id: "\(isReady):\(search)") {
            guard isReady else { return }
            isLoading = true
            do {
                try await Task.sleep(for: .milliseconds(200))
                let results = try await controller.conversationHistory(matching: search)
                try Task.checkCancellation()
                conversations = results
                errorMessage = nil
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func open(_ conversation: RepositoryAIConversationSummary) {
        isOpening = true
        Task {
            defer { isOpening = false }
            do {
                try await controller.restoreConversation(id: conversation.id)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ conversation: RepositoryAIConversationSummary) {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await controller.deleteConversation(id: conversation.id)
                conversations.removeAll { $0.id == conversation.id }
                conversationPendingDeletion = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
