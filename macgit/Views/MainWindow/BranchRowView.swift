//
//  BranchRowView.swift
//  macgit
//
//  Created by Thanh Tran on 26/6/26.
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

struct BranchRowContent: View, Equatable {
    let row: BranchRowItem
    let isCurrentBranch: Bool
    let isActiveDropRow: Bool
    let dropLabel: String
    let isBranchSyncing: Bool
    let syncStatus: BranchSyncStatus?
    let integrationStatus: CurrentBranchIntegrationStatus?
    let canUpdateCurrentBranch: Bool
    let updateCurrentBranch: () -> Void
    let headBadgeVisible: Bool
    let folderIsExpanded: Bool
    let isCurrentBranchPrefix: Bool
    let gitFlowRole: GitFlowBranchRole?
    @Environment(\.appTextScale) private var textScale

    static func == (lhs: BranchRowContent, rhs: BranchRowContent) -> Bool {
        lhs.row == rhs.row
            && lhs.isCurrentBranch == rhs.isCurrentBranch
            && lhs.isActiveDropRow == rhs.isActiveDropRow
            && lhs.dropLabel == rhs.dropLabel
            && lhs.isBranchSyncing == rhs.isBranchSyncing
            && lhs.syncStatus == rhs.syncStatus
            && lhs.integrationStatus == rhs.integrationStatus
            && lhs.canUpdateCurrentBranch == rhs.canUpdateCurrentBranch
            && lhs.headBadgeVisible == rhs.headBadgeVisible
            && lhs.folderIsExpanded == rhs.folderIsExpanded
            && lhs.isCurrentBranchPrefix == rhs.isCurrentBranchPrefix
            && lhs.gitFlowRole == rhs.gitFlowRole
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(0..<row.indent, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16)
                }
            }

            leadingIcon

            Text(row.name)
                .font(.system(size: 12).scaled(by: textScale))
                .fontWeight(isCurrentBranch && !row.isFolder || isCurrentBranchPrefix ? .semibold : .regular)
                .foregroundStyle(isCurrentBranchPrefix ? Color.accentColor : .primary)
                .lineLimit(1)

            if let gitFlowRole, !row.isFolder {
                GitFlowBranchRoleBadge(role: gitFlowRole)
            }

            Spacer()

            if !row.isFolder {
                if isActiveDropRow {
                    BranchDropLabel(text: dropLabel)
                } else {
                    BranchSyncBadge(isSyncing: isBranchSyncing, status: syncStatus)
                    if let integrationStatus, integrationStatus.predictsBaseConflict {
                        CurrentBranchIntegrationWarning(
                            status: integrationStatus,
                            canUpdate: canUpdateCurrentBranch,
                            onUpdate: updateCurrentBranch
                        )
                    }
                    if headBadgeVisible {
                        BranchHeadBadge()
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .background(isActiveDropRow ? Color.accentColor.opacity(0.24) : Color.clear)
        .overlay {
            if isActiveDropRow {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if row.isFolder {
            Image(systemName: folderIsExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isCurrentBranchPrefix ? Color.accentColor : .secondary)
                .frame(width: 16, alignment: .center)
        } else if isCurrentBranch {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, alignment: .center)
        } else {
            Color.clear
                .frame(width: 16)
        }
    }
}

struct BranchDropLabel: View {
    let text: String
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold).scaled(by: textScale))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

private struct BranchHeadBadge: View {
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        Text("HEAD")
            .font(.system(size: 10, weight: .semibold).scaled(by: textScale))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

private struct BranchSyncBadge: View {
    let isSyncing: Bool
    let status: BranchSyncStatus?
    @Environment(\.appTextScale) private var textScale

    var body: some View {
        if isSyncing {
            HStack(spacing: 0) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 10)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary)
            .cornerRadius(4)
        } else if let status {
            HStack(spacing: 4) {
                if status.ahead > 0 {
                    HStack(spacing: 2) {
                        Text("\(status.ahead)")
                        Text("\u{2191}")
                    }
                    .font(.system(size: 10, weight: .medium).scaled(by: textScale))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary)
                    .cornerRadius(4)
                }

                if status.behind > 0 {
                    HStack(spacing: 2) {
                        Text("\(status.behind)")
                        Text("\u{2193}")
                    }
                    .font(.system(size: 10, weight: .medium).scaled(by: textScale))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary)
                    .cornerRadius(4)
                }
            }
        }
    }
}
