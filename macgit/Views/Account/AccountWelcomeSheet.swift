// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct AccountWelcomeSheet: View {
    @ObservedObject var controller: AccountSessionController
    let state: AccountWelcomeState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: state == .pro ? "star.circle.fill" : "checkmark.circle.fill")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundStyle(state == .pro ? .yellow : Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Error: \(errorMessage)")
            }

            HStack(spacing: 12) {
                if state == .free {
                    Button(
                        controller.openingWebDestination == .pricing ? "Opening Pricing..." : "Upgrade to Pro",
                        systemImage: "star.fill",
                        action: openPricing
                    )
                    .disabled(controller.isOpeningAccountOnWeb)
                }

                Button(continueTitle, action: onDismiss)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.isOpeningAccountOnWeb)
            }
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 440)
        .overlay(alignment: .topTrailing) {
            Button("Close", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                .help("Close")
                .disabled(controller.isOpeningAccountOnWeb)
                .padding(16)
        }
        .interactiveDismissDisabled(controller.isOpeningAccountOnWeb)
    }

    private var title: String {
        state == .pro ? "Welcome to Commit+ Pro" : "Welcome to Commit+"
    }

    private var message: String {
        switch state {
        case .neutral:
            "You’re signed in and ready to go."
        case .free:
            "You’re signed in and ready to go. Upgrade to Pro to explore new and exclusive features and get more from Commit+."
        case .pro:
            "You’re all set. Enjoy your Pro features, and make your next commit a great one."
        }
    }

    private var continueTitle: String {
        state == .pro ? "Let’s Go" : "Get Started"
    }

    private func openPricing() {
        Task { await controller.openPricingOnWeb() }
    }
}
