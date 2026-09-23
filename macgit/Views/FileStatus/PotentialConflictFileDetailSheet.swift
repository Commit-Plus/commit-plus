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

struct PotentialConflictFileDetailSheet: View {
    let presentation: PotentialConflictFilePresentation
    let repositoryURL: URL
    let canUpdateCurrentBranch: Bool
    let onUpdateCurrentBranch: (CurrentBranchIntegrationStatus) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var analysis: PotentialConflictFileAnalysis?
    @State private var visibleConflictBlockCount = 4

    private let conflictBlockPageSize = 4

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            details
            Divider()
            footer
        }
        .frame(
            minWidth: 760,
            idealWidth: 900,
            minHeight: 560,
            idealHeight: 640,
            maxHeight: 640,
            alignment: .top
        )
        .task(id: presentation.id) {
            visibleConflictBlockCount = conflictBlockPageSize
            analysis = await GitStatusService.shared.potentialConflictFileAnalysis(
                for: presentation.file,
                status: presentation.status,
                in: repositoryURL
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Potential update conflict", systemImage: "exclamationmark.triangle")
                .font(.title3)
                .bold()
                .foregroundStyle(.orange)

            Text(presentation.file.path)
                .font(.headline)
                .textSelection(.enabled)

            if let baseRef = presentation.status.baseRef {
                (
                    Text("Local changes may interact with updates from ")
                        + Text(baseRef).bold()
                        + Text(". The file is not currently conflicted.")
                )
                .foregroundStyle(.secondary)
            } else {
                Text("Local changes may interact with updates from the base branch. The file is not currently conflicted.")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    @ViewBuilder
    private var details: some View {
        if let analysis {
            VStack(alignment: .leading, spacing: 12) {
                analysisSummary(analysis)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text("Analyzing local and incoming changes…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func analysisSummary(_ analysis: PotentialConflictFileAnalysis) -> some View {
        if !analysis.conflictBlocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Textual overlap predicted", systemImage: "exclamationmark.triangle.fill")
                    .bold()
                    .foregroundStyle(.orange)

                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(analysis.conflictBlocks.prefix(visibleConflictBlockCount))) { block in
                            PotentialConflictCodeBlockView(
                                block: block,
                                fileExtension: SyntaxHighlighter.syntaxIdentifier(forFilePath: presentation.file.path)
                            )
                        }

                        if visibleConflictBlockCount < analysis.conflictBlocks.count {
                            Button("Load more conflict blocks", systemImage: "ellipsis") {
                                loadMoreConflictBlocks(totalCount: analysis.conflictBlocks.count)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .background(.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if analysis.exactAnalysisPerformed {
            Label(
                "No exact textual overlap was produced, but both local and incoming changes touch this file. Review the local changes before updating.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        } else {
            Label(
                "Exact line-level analysis is unavailable for this file. Review the local changes before updating.",
                systemImage: "info.circle"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func loadMoreConflictBlocks(totalCount: Int) {
        visibleConflictBlockCount = min(
            visibleConflictBlockCount + conflictBlockPageSize,
            totalCount
        )
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !canUpdateCurrentBranch {
                Text("Commit or stash changes and finish other Git operations before updating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close", role: .cancel, action: dismiss.callAsFunction)
                .keyboardShortcut(.cancelAction)

            Button("Update Current Branch", systemImage: "arrow.triangle.2.circlepath", action: updateCurrentBranch)
                .buttonStyle(.borderedProminent)
                .disabled(!canUpdateCurrentBranch)
        }
        .padding()
    }

    private func updateCurrentBranch() {
        dismiss()
        onUpdateCurrentBranch(presentation.status)
    }
}
