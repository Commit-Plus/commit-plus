// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import SwiftUI

struct TermsAcceptanceGate<Content: View>: View {
    @AppStorage("hasAcceptedTermsOfService") private var hasAcceptedTerms = false

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .disabled(!hasAcceptedTerms)
            .overlay {
                if !hasAcceptedTerms {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()

                        TermsAcceptanceView(
                            onContinue: { hasAcceptedTerms = true },
                            onDecline: { NSApplication.shared.terminate(nil) }
                        )
                        .background(
                            Color(nsColor: .windowBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 24)
                        )
                        .shadow(radius: 20)
                    }
                }
            }
            .onDisappear {
                if !hasAcceptedTerms {
                    NSApplication.shared.terminate(nil)
                }
            }
    }
}

private struct TermsAcceptanceView: View {
    let onContinue: () -> Void
    let onDecline: () -> Void
    private let baseURL = try? CommitPlusWebConfiguration.baseURL()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Welcome to Commit+")
                .font(.title2.bold())

            Text("By clicking Continue below, you agree to our Terms of Service and Privacy Policy.")
                .fixedSize(horizontal: false, vertical: true)

            if let baseURL {
                HStack(spacing: 16) {
                    Link("Terms of Service", destination: baseURL.appending(path: "terms"))
                    Link("Privacy Policy", destination: baseURL.appending(path: "policy"))
                }
            } else {
                Text("The Commit+ website URL is not configured correctly.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Do Not Accept", action: onDecline)
                Spacer()
                if baseURL != nil {
                    Button("Continue", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}
