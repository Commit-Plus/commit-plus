// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

/// One-line commit identity: avatar, author, short hash, date and subject.
struct CommitSummaryBar: View {
    let commit: Commit
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        HStack(spacing: 8) {
            ReflogActorAvatar(name: commit.author, email: commit.email, size: 18)
            Text(commit.author).lineLimit(1).layoutPriority(1)
            Text(commit.shortHash)
                .font(.system(size: 12, design: .monospaced).scaled(by: textScale))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(commit.date, format: .dateTime.year().month().day().hour().minute())
                .foregroundStyle(.secondary).lineLimit(1)
            Text(commit.displaySubject)
                .fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12).scaled(by: textScale))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(.separator).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
    }
}

extension Commit {
    var displaySubject: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "<empty message>" : message
    }
}

/// File icon followed by the path, with the directory dimmed and the file name emphasized.
struct FilePathLabel: View {
    let path: String
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        let name = (path as NSString).lastPathComponent
        let directory = String(path.dropLast(name.count))
        HStack(spacing: 5) {
            RevisionTreeIcon(path: path, isDirectory: false).frame(width: 16, height: 16)
            (Text(directory).foregroundStyle(.secondary) + Text(name).fontWeight(.medium))
                .font(.system(size: 12).scaled(by: textScale))
                .lineLimit(1).truncationMode(.middle)
        }
        .help(path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path)
    }
}

/// Compact status marker for a changed file, matching the file list colors.
struct CommitFileStatusBadge: View {
    let status: CommitFileStatus

    var body: some View {
        Image(systemName: status.changeStyle.symbol)
            .foregroundStyle(Color(nsColor: status.changeStyle.color))
            .accessibilityLabel(status.changeStyle.label)
            .help(status.changeStyle.label)
    }
}

/// The "Commit" tab: author, refs, SHA, parents and the full message.
struct CommitInfoView: View {
    let commit: Commit
    let fullMessage: String?
    let isLoadingMessage: Bool
    var onSelectParent: ((String) -> Void)? = nil
    @Environment(\.appTextScale) private var textScale
    @State private var copiedHash = false

    private static let labelWidth: CGFloat = 76

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    ReflogActorAvatar(name: commit.author, email: commit.email, size: 40)
                        .frame(width: Self.labelWidth, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AUTHOR").font(.system(size: 10, weight: .medium).scaled(by: textScale))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(commit.author).font(.system(size: 14, weight: .medium).scaled(by: textScale))
                            Text(commit.email).font(.system(size: 12).scaled(by: textScale))
                                .foregroundStyle(.secondary)
                        }
                        .textSelection(.enabled)
                        Text(commit.date, format: .dateTime.day().month(.wide).year().hour().minute().second().timeZone())
                            .font(.system(size: 12).scaled(by: textScale)).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if !commit.refs.isEmpty {
                        row("REFS") {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 4) { ForEach(commit.refs, id: \.self) { RefLabel(text: $0) } }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 4) { ForEach(commit.refs, id: \.self) { RefLabel(text: $0) } }
                                }
                            }
                        }
                    }
                    row("SHA") {
                        HStack(spacing: 6) {
                            Text(commit.hash)
                                .font(.system(size: 12, design: .monospaced).scaled(by: textScale))
                                .textSelection(.enabled).lineLimit(1)
                            Button(copiedHash ? "Copied" : "Copy SHA",
                                   systemImage: copiedHash ? "checkmark" : "doc.on.doc") { copyHash() }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .pointingHandCursor()
                                .help("Copy commit SHA")
                        }
                    }
                    if !commit.parents.isEmpty {
                        row(commit.parents.count == 1 ? "PARENT" : "PARENTS") {
                            HStack(spacing: 10) {
                                ForEach(commit.parents, id: \.self) { parent in
                                    Button(String(parent.prefix(7))) { onSelectParent?(parent) }
                                        .buttonStyle(.link)
                                        .font(.system(size: 12, design: .monospaced).scaled(by: textScale))
                                        .disabled(onSelectParent == nil)
                                        .pointingHandCursor()
                                        .help("Select parent commit \(parent)")
                                }
                            }
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(subject).font(.system(size: 15, weight: .medium).scaled(by: textScale))
                    if let body = messageBody {
                        Text(body).font(.system(size: 12, design: .monospaced).scaled(by: textScale))
                    } else if fullMessage == nil, isLoadingMessage {
                        ProgressView().controlSize(.small)
                    }
                }
                .textSelection(.enabled)
                .padding(.leading, Self.labelWidth + 12)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title).font(.system(size: 10, weight: .medium).scaled(by: textScale))
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
        }
    }

    private var subject: String {
        guard let first = fullMessage?.split(separator: "\n", omittingEmptySubsequences: true).first else {
            return commit.displaySubject
        }
        return String(first)
    }

    private var messageBody: String? {
        guard let fullMessage, let newline = fullMessage.firstIndex(of: "\n") else { return nil }
        let body = fullMessage[newline...].trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? nil : body
    }

    private func copyHash() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.hash, forType: .string)
        copiedHash = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedHash = false
        }
    }
}
