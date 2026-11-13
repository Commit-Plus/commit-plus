// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// Window content listing the commits that touched one file, with the selected commit's diff.
struct FileHistoryView: View {
    @Bindable var controller: FileHistoryController
    let actions: RevisionFileActionCenter
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("History").font(.headline.scaled(by: textScale))
                FilePathLabel(path: controller.path)
                Spacer(minLength: 8)
                Label(String(controller.revision.prefix(7)), systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12, design: .monospaced).scaled(by: textScale))
                    .foregroundStyle(.secondary)
                    .help("History starting at \(controller.revision)")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if controller.isLoading && controller.entries.isEmpty {
                ProgressView("Loading history…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = controller.error {
                VStack {
                    EmptyStateView(icon: "exclamationmark.triangle", message: "Unable to load file history", detail: error)
                    Button("Retry") { controller.load() }.pointingHandCursor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if controller.entries.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", message: "No commits changed this file")
            } else {
                PersistentHSplit(autosaveName: "FileHistoryWindowSplit",
                    minimumLeftWidth: 260, minimumRightWidth: 320,
                    left: { commitList.frame(maxWidth: .infinity, maxHeight: .infinity) },
                    right: { diff.frame(maxWidth: .infinity, maxHeight: .infinity) })
            }
        }
        .task { controller.load() }
    }

    private var commitList: some View {
        List(controller.entries, selection: $controller.selectedID) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    ReflogActorAvatar(name: entry.commit.author, email: entry.commit.email, size: 16)
                    Text(entry.commit.author).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.commit.date, format: .dateTime.day().month().year())
                        .foregroundStyle(.secondary).lineLimit(1)
                    Text(entry.commit.shortHash)
                        .font(.system(size: 11, design: .monospaced).scaled(by: textScale))
                        .foregroundStyle(.secondary)
                }
                Text(entry.commit.displaySubject).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 5) {
                    CommitFileStatusBadge(status: entry.status)
                    Text(entry.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .font(.system(size: 12).scaled(by: textScale))
            .padding(.vertical, 3)
            .contextMenu {
                Button("Blame at This Revision…") {
                    actions.showBlame(path: entry.path, revision: entry.commit.hash)
                }
                .disabled(entry.status == .deleted)
                Button("Save As…") { actions.saveCopy(path: entry.path, revision: entry.commit.hash) }
                    .disabled(entry.status == .deleted)
                Divider()
                Button("Copy Commit SHA") { actions.copyPath(entry.commit.hash) }
                Button("Copy Path") { actions.copyPath(entry.path) }
            }
            .help(entry.oldPath.map { "Renamed from \($0)" } ?? entry.path)
        }
        .listStyle(.inset)
    }

    @ViewBuilder private var diff: some View {
        if let entry = controller.selectedEntry {
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    FilePathLabel(path: entry.path)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                if controller.diff?.id == entry.id {
                    DiffView(hunks: controller.diff?.hunks ?? [], repositoryURL: controller.repositoryURL,
                        filePath: entry.path, gitRef: entry.commit.hash,
                        imageOldPath: entry.oldPath, imageFileStatus: entry.status)
                } else {
                    ProgressView("Loading diff…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            EmptyStateView(icon: "doc.text", message: "Select a commit")
        }
    }
}
