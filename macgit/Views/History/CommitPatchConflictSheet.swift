//
//  CommitPatchConflictSheet.swift
//  macgit
//
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software; you can redistribute it and/or modify
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

/// Edits an in-memory merge result. The existing code panes/editor never receive a repository mutation callback.
struct CommitPatchConflictSheet: View {
    let file: CommitPatchReviewFile
    let isBusy: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onSkip: () -> Void
    let onResolve: (String) -> Void
    @State private var result: String
    @State private var scrollController = SyncedScrollController()
    @State private var undoResetGeneration = 0
    @State private var commandContext = ConflictUndoCommandContext.makeIdentifier()
    @State private var undoResults: [String] = []
    @State private var redoResults: [String] = []

    init(file: CommitPatchReviewFile, isBusy: Bool, errorMessage: String?, onCancel: @escaping () -> Void,
         onSkip: @escaping () -> Void, onResolve: @escaping (String) -> Void) {
        self.file = file
        self.isBusy = isBusy
        self.errorMessage = errorMessage
        self.onCancel = onCancel
        self.onSkip = onSkip
        self.onResolve = onResolve
        self._result = State(initialValue: file.conflict?.markedResult ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(file.reviewTitle).font(.title2.bold())
            Text(file.file.path).font(.callout.monospaced()).textSelection(.enabled)
            if let conflict = file.conflict {
                Text(conflict.message).foregroundStyle(.secondary)
                if conflict.markedResult != nil {
                    HStack(spacing: 12) {
                        codePane("Your working copy", text: conflict.current, color: .blue)
                        codePane("Selected changes applied to their original version", text: conflict.selected, color: .green)
                    }
                    .frame(maxHeight: .infinity)
                    HStack {
                        Button("Keep current conflicts") { choose(.current) }
                        Button("Use selected conflicts") { choose(.incoming) }
                        Spacer()
                    }
                    Text("Choose a side for the conflicting sections or edit the result below. Non-conflicting changes are kept. Remove all conflict markers before continuing.")
                        .font(.caption).foregroundStyle(.secondary)
                    ConflictResultEditorView(text: result, onTextChange: { result = $0 },
                        fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: file.file.path),
                        baselineText: conflict.current, isDisabled: isBusy, undoResetGeneration: undoResetGeneration,
                        scrollController: scrollController)
                        .frame(maxHeight: .infinity)
                } else {
                    if conflict.kind == .missingFile {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "doc.badge.questionmark")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("File isn’t on this branch")
                                    .font(.headline)
                                Text("The commit changes an existing file, but this branch has no copy of it. The green lines below are only the changes from the commit; they aren’t a merge conflict. Apply Selected Changes can add changes to an existing file, but it can’t recreate the missing file from those lines alone.")
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Changes from the source commit · This is not a conflict diff")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    if DiffParser.parse(file.patch).isEmpty {
                        ScrollView {
                            Text(file.patch).font(.callout.monospaced()).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        DiffView(hunks: DiffParser.parse(file.patch), filePath: file.file.path, prefersTextDiff: true)
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            HStack {
                Text("Only a preview. Your files and staging area are unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Skip this file", action: onSkip)
                if file.conflict?.markedResult != nil {
                    Button("Review Result") { finish(result) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(CommitPatchReviewFile.containsConflictMarkers(result))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(isBusy)
        .background(CommitPatchConflictWindowContext(identifier: commandContext))
        .onReceive(NotificationCenter.default.publisher(for: .conflictUndoAction)) { notification in
            guard !isBusy, notification.userInfo?["commandContext"] as? String == commandContext.rawValue,
                  let action = notification.userInfo?["action"] as? GitUndoMenuAction else { return }
            switch action {
            case .undo:
                guard let previous = undoResults.popLast() else { return }
                redoResults.append(result)
                result = previous
            case .redo:
                guard let next = redoResults.popLast() else { return }
                undoResults.append(result)
                result = next
            }
            undoResetGeneration += 1
        }
    }

    private func codePane(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold())
            SyncedScrollView(id: title, controller: scrollController,
                virtualizedRowCount: text.components(separatedBy: "\n").count) {
                ConflictCodeView(text: text, fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: file.file.path),
                    highlightedLines: [], highlightColor: color)
            }
            .background(.quaternary.opacity(0.3))
        }
    }

    private func choose(_ side: ConflictSectionResolution) {
        guard let marked = file.conflict?.markedResult,
              var document = try? ConflictResolutionDocument.parse(marked) else { return }
        document.selectAllConflicts(side)
        undoResults.append(result)
        redoResults.removeAll()
        result = document.resolvedText
        undoResetGeneration += 1
    }

    private func finish(_ text: String) {
        onResolve(text)
    }
}
