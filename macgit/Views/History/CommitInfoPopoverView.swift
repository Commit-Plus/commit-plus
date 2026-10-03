//
//  CommitInfoPopoverView.swift
//  macgit
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
import SwiftUI

struct CommitInfoPopoverView: View {
    private enum CopyTarget: Equatable {
        case message
        case hash
    }

    @Environment(\.appTextScale) private var textScale

    let commit: Commit
    let fullMessage: String?
    let isLoadingMessage: Bool
    let onCopyMessage: () -> Void
    let onCopyHash: () -> Void
    @State private var copiedTarget: CopyTarget?
    @State private var copyStatusTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.tint)
                Text("Commit details")
                    .font(.headline.scaled(by: textScale))
                Spacer()
                Text(commit.shortHash)
                    .font(.system(.caption, design: .monospaced).scaled(by: textScale))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Author") {
                    Text("\(commit.author) <\(commit.email)>")
                        .textSelection(.enabled)
                }

                LabeledContent("Date") {
                    Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                }

                LabeledContent("Commit") {
                    Text(commit.hash)
                        .font(.system(.body, design: .monospaced).scaled(by: textScale))
                        .textSelection(.enabled)
                }

                if !commit.parents.isEmpty {
                    LabeledContent(commit.parents.count == 1 ? "Parent" : "Parents") {
                        Text(commit.parents.map { String($0.prefix(12)) }.joined(separator: ", "))
                            .font(.system(.body, design: .monospaced).scaled(by: textScale))
                            .textSelection(.enabled)
                    }
                }

                if !commit.refs.isEmpty {
                    LabeledContent("Refs") {
                        Text(commit.refs.joined(separator: ", "))
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            .font(.body.scaled(by: textScale))

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Commit message")
                        .font(.subheadline.weight(.semibold).scaled(by: textScale))
                    Spacer()
                    if isLoadingMessage {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Group {
                    if let fullMessage {
                        ScrollView {
                            Text(displayCommitMessage(fullMessage))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    } else if isLoadingMessage {
                        ProgressView("Loading full message…")
                            .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                    } else {
                        Text("The full commit message is unavailable.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
                    }
                }
                .font(.body.scaled(by: textScale))
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 220)
            }

            HStack {
                Spacer()
                Button(
                    copiedTarget == .message ? "Message copied" : "Copy message",
                    systemImage: copiedTarget == .message ? "checkmark.circle.fill" : "doc.on.doc"
                ) {
                    copy(target: .message)
                }
                .foregroundStyle(copiedTarget == .message ? .green : .primary)
                .onContinuousHover(perform: updateCopyCursor)

                Button(
                    copiedTarget == .hash ? "Hash copied" : "Copy hash",
                    systemImage: copiedTarget == .hash ? "checkmark.circle.fill" : "number"
                ) {
                    copy(target: .hash)
                }
                .foregroundStyle(copiedTarget == .hash ? .green : .primary)
                .onContinuousHover(perform: updateCopyCursor)
            }
            .font(.body.scaled(by: textScale))
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 440)
        .onDisappear {
            copyStatusTask?.cancel()
        }
    }

    private func copy(target: CopyTarget) {
        switch target {
        case .message:
            onCopyMessage()
        case .hash:
            onCopyHash()
        }

        copiedTarget = target
        copyStatusTask?.cancel()
        copyStatusTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if copiedTarget == target {
                    copiedTarget = nil
                }
            }
        }
    }

    private func displayCommitMessage(_ message: String) -> String {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<empty message>"
            : message
    }

    private func updateCopyCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            NSCursor.pointingHand.set()
        case .ended:
            NSCursor.arrow.set()
        }
    }
}
