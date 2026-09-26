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

struct ProUpgradePresentation: Identifiable {
    let feature: PlanFeature

    var id: PlanFeature { feature }
}

struct ProUpgradeSheet: View {
    let feature: PlanFeature
    let isSignedIn: Bool
    let isOpening: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onPrimaryAction: () -> Void

    private static let comparisonRows = [
        (feature: "Number of devices", free: "1", pro: "3"),
        (feature: "BYOK AI providers", free: "OpenAI & Gemini", pro: "Full"),
        (feature: "View and manage PRs", free: "Public repositories", pro: "Full"),
        (feature: "Git LFS", free: "Public repositories", pro: "Full"),
        (feature: "Git Flow", free: "Public & local repositories", pro: "Full"),
        (feature: "Git provider accounts", free: "1", pro: "Unlimited"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.indigo.opacity(0.10),
                    Color(nsColor: .windowBackgroundColor),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Color.accentColor.gradient, in: Circle())
                        .accessibilityHidden(true)

                    Text("Unlock \(feature.displayName)")
                        .font(.title)
                        .bold()

                    Text(upgradeDescription)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("From")
                        .foregroundStyle(.secondary)
                    Text("$3.25")
                        .font(.largeTitle)
                        .bold()
                    Text("/ month")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 0) {
                    comparisonHeader

                    ForEach(Self.comparisonRows.indices, id: \.self) { index in
                        comparisonRow(at: index)
                    }

                    Divider()

                    Text("And more…")
                        .font(.callout)
                        .bold()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 11)
                        .padding(.horizontal, 14)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator, lineWidth: 1)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("Not Now", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isOpening)

                    Spacer()

                    Button(action: onPrimaryAction) {
                        if isOpening {
                            Label("Opening Pricing…", systemImage: "arrow.up.right.square")
                        } else {
                            Label(
                                isSignedIn ? "View Pricing" : "Sign In",
                                systemImage: isSignedIn ? "arrow.up.right.square" : "person.crop.circle"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isOpening)
                }
            }
            .padding(28)
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: 700)
        .interactiveDismissDisabled(isOpening)
    }

    private var comparisonHeader: some View {
        HStack(spacing: 0) {
            Text("Feature")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Free")
                .frame(width: 180)
            Text("Pro")
                .bold()
                .foregroundStyle(Color.accentColor)
                .frame(width: 100)
        }
        .font(.headline)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.primary.opacity(0.08))
    }

    private var upgradeDescription: String {
        switch feature {
        case .pullRequests, .gitFlow, .gitLFS:
            "Upgrade to Commit+ Pro to use \(feature.displayName) in private repositories, plus advanced workflows and AI tools across your Macs."
        case .aiCommitMessage, .repositoryChat, .repositoryAIActions, .aiConflictResolution, .aiBringYourOwnKey,
             .multipleProviderAccounts:
            "Upgrade to Commit+ Pro to use \(feature.displayName), plus advanced workflows and AI tools across your Macs."
        case .privateRepositories:
            "Upgrade to Commit+ Pro for advanced workflows and AI tools in private repositories across your Macs."
        }
    }

    private func comparisonRow(at index: Int) -> some View {
        let row = Self.comparisonRows[index]
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Text(row.feature)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.free)
                    .foregroundStyle(.secondary)
                    .frame(width: 180)
                    .accessibilityLabel(row.free == "—" ? "Not available" : row.free)
                if row.pro == "Full" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 100)
                        .accessibilityLabel("Full access")
                } else {
                    Text(row.pro)
                        .bold()
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 100)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
        }
    }
}
