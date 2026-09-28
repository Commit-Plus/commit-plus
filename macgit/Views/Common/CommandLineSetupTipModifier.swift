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
    let isBlocked: Bool
    @AppStorage("hasAcceptedTermsOfService") private var hasAcceptedTerms = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingTip = false

    func body(content: Content) -> some View {
        content
            .replacingSheet(isPresented: $showingTip) {
                CommandLineSetupTip()
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
