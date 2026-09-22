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

struct RepositoryToolbarShortcutPanel: View {
    static let minimumWidth: CGFloat = 280
    static let defaultWidth: CGFloat = 340
    static let maximumWidth: CGFloat = 560
    static let cornerRadius: CGFloat = 28

    static func clampedWidth(_ width: CGFloat) -> CGFloat {
        guard width.isFinite else { return defaultWidth }
        return min(maximumWidth, max(minimumWidth, width))
    }

    let onDismiss: () -> Void
    @ObservedObject var repositoryAIController: RepositoryAIChatController
    @ObservedObject var aiProviderController: AIProviderController
    let repositoryChatAccess: FeatureAccessDecision
    let isSignedIn: Bool
    let onRequestRepositoryChatAccess: () -> Void
    let onExecuteRemoteOperation: (RepositoryAIValidatedRemoteOperation) async throws -> RepositoryAIRemoteOperationExecutionResult

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Self.cornerRadius,
            bottomLeadingRadius: Self.cornerRadius
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .opacity(0.65)
            RepositoryAIChatView(
                controller: repositoryAIController,
                providerController: aiProviderController,
                accessDecision: repositoryChatAccess,
                isSignedIn: isSignedIn,
                onRequestAccess: onRequestRepositoryChatAccess,
                onExecuteRemoteOperation: onExecuteRemoteOperation
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            PanelMouseEventBarrier()
        }
        .glassEffect(
            .regular.tint(Color(nsColor: .controlBackgroundColor).opacity(0.24)),
            in: panelShape
        )
        .overlay {
            panelShape
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .clipShape(panelShape)
        .shadow(color: .black.opacity(0.2), radius: 18, x: -5)
    }

    private var header: some View {
        HStack {
            Label("AI Chat", systemImage: "sparkles")
                .font(.headline)

            Spacer()

            Button("Close AI Chat", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .pointingHandCursor()
                .controlSize(.small)
                .frame(width: 44, height: 32)
                .background(controlBackground(cornerRadius: 11))
                .help("Close")
        }
        .padding(16)
    }

    private func controlBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.primary.opacity(0.075))
            .stroke(.primary.opacity(0.1), lineWidth: 1)
    }
}
