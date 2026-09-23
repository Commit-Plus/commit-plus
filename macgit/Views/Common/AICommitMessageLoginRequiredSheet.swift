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

struct AICommitMessageLoginRequiredSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: AccountSessionController
    let feature: PlanFeature
    @State private var showingAuthentication = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.indigo.opacity(0.24),
                    Color.accentColor.opacity(0.14),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(.largeTitle, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(16)
                        .background(Color.accentColor.gradient, in: Circle())
                        .shadow(color: Color.accentColor.opacity(0.28), radius: 16, y: 8)
                        .accessibilityHidden(true)

                    Text("Sign In to Use AI")
                        .font(.title)
                        .bold()

                    Text("\(feature.displayName) is a Commit+ Pro feature. Sign in so we can securely check your plan before using it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Your plan is verified with your Commit+ account", systemImage: "checkmark.shield.fill")
                    Label("Repository content stays on this Mac with Apple Intelligence", systemImage: "lock.macwindow")
                    Label("No repository files are uploaded for plan verification", systemImage: "folder.badge.questionmark")
                }
                .foregroundStyle(.secondary)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.separator, lineWidth: 1)
                }

                HStack {
                    Button("Not Now") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Sign In", systemImage: "person.crop.circle", action: showAuthentication)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(30)
        }
        .frame(minWidth: 540, idealWidth: 580)
        .replacingSheet(isPresented: $showingAuthentication) {
            AuthenticationSheet(controller: controller, mode: .signIn)
        }
        .onChange(of: controller.account?.uid) { _, accountUID in
            if accountUID != nil {
                dismiss()
            }
        }
    }

    private func showAuthentication() {
        controller.errorMessage = nil
        showingAuthentication = true
    }
}
