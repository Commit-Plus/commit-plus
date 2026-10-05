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

struct CommandLineSetupTipModifier: ViewModifier {
    let windowContext: RepositoryWindowContext
    let isBlocked: Bool
    @AppStorage("hasAcceptedTermsOfService") private var hasAcceptedTerms = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTip = false
    @State private var installOnPresentation = false

    func body(content: Content) -> some View {
        content
            .replacingSheet(isPresented: $showingTip) {
                CommandLineSetupTip(installOnPresentation: installOnPresentation)
            }
            .onReceive(NotificationCenter.default.publisher(for: .installCommandLineTool)) { notification in
                guard windowContext.owns(notification) else { return }
                installOnPresentation = true
                showingTip = true
            }
            .onChange(of: showingTip) { _, isPresented in
                if !isPresented { installOnPresentation = false }
            }
            .task {
                await Task.yield()
                presentIfNeeded()
            }
            .onChange(of: isBlocked) { _, _ in presentIfNeeded() }
            .onChange(of: hasAcceptedTerms) { _, _ in presentIfNeeded() }
            .onChange(of: scenePhase) { _, _ in presentIfNeeded() }
    }

    private func presentIfNeeded() {
        // The terms gate disables its content, including sheets presented from it.
        // Claim the reminder only after that gate has been accepted.
        guard hasAcceptedTerms, !isBlocked, scenePhase == .active else { return }
        let model = CommandLineSetupModel()
        showingTip = showingTip || CommandLineReminderPolicy.shared.claimPresentation(isReady: model.isReady)
    }
}

extension Notification.Name {
    static let installCommandLineTool = Notification.Name("installCommandLineTool")
}
