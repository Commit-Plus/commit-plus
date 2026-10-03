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
import UniformTypeIdentifiers

struct SidebarBranchesSection: View {
    @Environment(\.appTextScale) private var textScale
    let rows: [BranchRowItem]
    let isExpanded: Bool
    let isLoading: Bool
    let currentBranch: String
    let gitFlowConfiguration: GitFlowConfiguration
    let headHash: String
    let expandedFolders: Set<String>
    let branchSyncStatus: [String: BranchSyncStatus]
    let currentBranchFallbackSyncStatus: BranchSyncStatus?
    let currentBranchIntegrationStatus: CurrentBranchIntegrationStatus?
    let canUpdateCurrentBranch: Bool
    let upstreamByBranch: [String: String]
    let remoteNames: [String]
    let branchesByRemote: [String: [String]]
    let isCurrentBranchDropTargeted: Bool
    let isHeaderDropTargeted: Bool
    let activeDropLabel: String?
    let draggedRemoteBranch: String?
    let isBranchSyncing: (String) -> Bool
    let deletableBranchesForPrefix: (String) -> [String]
    let makeBranchPayload: (String) -> GitDragPayload
    let finishBranchDrag: (GitDragPayload) -> Void
    let actions: SidebarBranchSectionActions

    var body: some View {
        Section {
            headerRow

            if isExpanded {
                if isLoading && rows.isEmpty {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                } else if rows.isEmpty {
                    Text("No branches")
                        .font(.caption.scaled(by: textScale))
                        .foregroundStyle(.secondary)
                } else {
                    if currentBranch.isEmpty && !headHash.isEmpty {
                        HStack(spacing: 4) {
                            HStack(spacing: 0) {
                                Color.clear
                                    .frame(width: 16)
                            }

                            Image(systemName: "circle.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 16, alignment: .center)

                            Text("HEAD")
                                .font(.system(size: 12, weight: .bold).scaled(by: textScale))
                                .lineLimit(1)

                            if !headHash.isEmpty {
                                Text(headHash)
                                    .font(.system(size: 11).scaled(by: textScale))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 2)
                        .padding(.leading, 6)
                        .contentShape(Rectangle())
                        .tag(SidebarSelection.head(headHash))
                        .onTapGesture {
                            actions.select(.head(headHash))
                        }
                        .sidebarPointingHandCursor()
                    }

                    ForEach(rows) { row in
                        SidebarBranchRow(
                            row: row,
                            currentBranch: currentBranch,
                            gitFlowConfiguration: gitFlowConfiguration,
                            currentBranchFallbackSyncStatus: currentBranchFallbackSyncStatus,
                            currentBranchIntegrationStatus: currentBranchIntegrationStatus,
                            canUpdateCurrentBranch: canUpdateCurrentBranch,
                            expandedFolders: expandedFolders,
                            isCurrentBranchDropTargeted: isCurrentBranchDropTargeted,
                            branchSyncStatus: branchSyncStatus,
                            upstreamByBranch: upstreamByBranch,
                            remoteNames: remoteNames,
                            branchesByRemote: branchesByRemote,
                            isBranchSyncing: isBranchSyncing,
                            deletableBranchesForPrefix: deletableBranchesForPrefix,
                            makeBranchPayload: makeBranchPayload,
                            finishBranchDrag: finishBranchDrag,
                            actions: actions
                        )
                        .padding(.leading, 6)
                        .sidebarPointingHandCursor()
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        Group {
            if let draggedRemoteBranch {
                RemoteBranchCheckoutDropZone(
                    remoteBranch: draggedRemoteBranch,
                    isTargeted: isHeaderDropTargeted
                )
            } else {
                SidebarSectionHeader(
                    section: .branches,
                    isExpanded: isExpanded,
                    activeDropLabel: activeDropLabel,
                    onToggle: actions.toggleSection
                ) {
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            draggedRemoteBranch == nil && isHeaderDropTargeted
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .overlay {
            SidebarBranchDropTarget(
                onTap: actions.toggleSection,
                onTargetedChange: actions.setHeaderDropTargeted,
                fallbackPayload: actions.drop.activePayload,
                canAcceptDrop: { payload in
                    actions.drop.canAccept(payload, .branchesHeader, false)
                },
                dragPayload: { nil },
                dragTitle: { "" },
                onDragEnded: { _ in },
                onDrop: { payload in
                    actions.drop.handlePayload(payload, .branchesHeader, false)
                    return true
                }
            )
            .onDrop(of: [.macgitGitDragPayload], isTargeted: nil) { providers in
                if let payload = actions.drop.activePayload(),
                   !actions.drop.canAccept(payload, .branchesHeader, false) {
                    actions.drop.clearPayload(payload)
                    return false
                }

                return actions.drop.handleProviders(providers, .branchesHeader, false)
            }
        }
        .sidebarPointingHandCursor()
    }
}
