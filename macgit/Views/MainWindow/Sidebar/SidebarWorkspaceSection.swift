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

struct SidebarWorkspaceSection: View {
    @ObservedObject var appState: AppState
    let onRequestSearch: () -> Void
    let onRequestCreatePullRequest: () -> Void
    let gitFlowCommandState: GitFlowCommandState
    let onGitFlowAction: (GitFlowMenuAction) -> Void
    @State private var isShowingVisibilityPopover = false

    var body: some View {
        Section {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: SidebarSection.workspace.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SidebarSection.workspace.iconColor)

                    Text(SidebarSection.workspace.rawValue)
                        .font(.system(size: 11))
                        .bold()
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)

                Spacer()

                Button("Customize Workspace", systemImage: "line.3.horizontal.decrease.circle") {
                    isShowingVisibilityPopover.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
                .help("Choose which Workspace items are shown")
                .sidebarPointingHandCursor()
                .popover(isPresented: $isShowingVisibilityPopover, arrowEdge: .trailing) {
                    WorkspaceVisibilityPopover(appState: appState)
                }
            }
            .padding(.vertical, 2)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            ForEach(SidebarSection.workspace.items) { item in
                if isVisible(item), item == .search {
                    Label(item.rawValue, systemImage: item.icon)
                        .padding(.leading, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRequestSearch()
                        }
                        .sidebarPointingHandCursor()
                } else if isVisible(item) {
                    Label(item.rawValue, systemImage: item.icon)
                        .padding(.leading, 6)
                        .tag(SidebarSelection.item(item))
                        .contextMenu {
                            if item == .pullRequests {
                                Button("Create Pull Request...", systemImage: "arrow.triangle.pull", action: onRequestCreatePullRequest)
                            }
                        }
                        .sidebarPointingHandCursor()
                }
            }

            if appState.showGitFlow {
                Label(SidebarItem.gitFlow.rawValue, systemImage: SidebarItem.gitFlow.icon)
                    .padding(.leading, 6)
                    .tag(SidebarSelection.item(.gitFlow))
                    .contextMenu {
                        GitFlowCommandMenuContent(
                            state: gitFlowCommandState,
                            hasOpenRepository: true,
                            perform: onGitFlowAction
                        )
                    }
                    .help("Open Git Flow actions")
                    .accessibilityLabel("Git Flow")
                    .accessibilityHint("Shows Git Flow actions and workflow status.")
                    .sidebarPointingHandCursor()
            }
        }
    }

    private func isVisible(_ item: SidebarItem) -> Bool {
        switch item {
        case .reflog:
            appState.showWorkspaceReflog
        case .pullRequests:
            appState.showWorkspacePullRequests
        case .gitLFS:
            appState.showWorkspaceGitLFS
        case .fileStatus, .history, .search, .gitFlow:
            true
        }
    }
}
