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

struct PotentialConflictFileIndicator: View {
    let baseRef: String?
    let onOpenDetails: () -> Void

    @State private var showingDetails = false

    var body: some View {
        Button("Potential conflict", systemImage: "exclamationmark.triangle", action: showDetails)
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .buttonStyle(.plain)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.orange.opacity(0.6), lineWidth: 1)
            }
            .fixedSize()
            .contentShape(Rectangle())
            .help(helpText)
            .accessibilityHint(helpText)
            .onContinuousHover(perform: updateCursor)
            .popover(isPresented: $showingDetails) {
                PotentialConflictFileDetails(
                    baseRef: baseRef,
                    onOpenDetails: openDetails
                )
            }
    }

    private var helpText: String {
        if let baseRef {
            "This file is not conflicted. It is changed locally and also changed by \(baseRef), so updating may require attention."
        } else {
            "This file is not conflicted. It is changed locally and by the incoming branch update, so updating may require attention."
        }
    }

    private func showDetails() {
        showingDetails.toggle()
    }

    private func openDetails() {
        showingDetails = false
        onOpenDetails()
    }

    private func updateCursor(_ phase: HoverPhase) {
        switch phase {
        case .active:
            NSCursor.pointingHand.set()
        case .ended:
            NSCursor.arrow.set()
        }
    }
}
