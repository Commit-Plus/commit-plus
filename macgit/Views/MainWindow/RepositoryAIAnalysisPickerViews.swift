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

struct RepositoryAIRefComparisonPickerView: View {
    @ObservedObject var controller: RepositoryAIChatController
    let onSubmit: () -> Void

    var body: some View {
        RepositoryAIAnalysisForm(title: "Compare refs", onCancel: controller.cancelRefComparison) {
            Text("Compare a three-dot review diff. Commit subjects use the distinct two-dot range.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Base ref (for example, main)", text: $controller.comparisonBaseDraft)
            TextField("Head ref (for example, feature or origin/main)", text: $controller.comparisonHeadDraft)
            Button("Compare refs", systemImage: "arrow.left.arrow.right", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
                .disabled(controller.comparisonBaseDraft.isEmpty || controller.comparisonHeadDraft.isEmpty || controller.isRunning)
        }
    }
}

struct RepositoryAIPullRequestPickerView: View {
    @ObservedObject var controller: RepositoryAIChatController
    let onSubmit: () -> Void

    var body: some View {
        RepositoryAIAnalysisForm(title: "Analyze pull request", onCancel: controller.cancelPullRequestAnalysis) {
            Text("Enter a PR number for the current connected repository, or leave it blank to analyze the PR currently open in Commit+.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Pull request number", text: $controller.pullRequestNumberDraft)
            Button("Analyze pull request", systemImage: "arrow.triangle.branch", action: onSubmit)
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
                .disabled(controller.isRunning)
        }
    }
}

private struct RepositoryAIAnalysisForm<Content: View>: View {
    let title: String
    let onCancel: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .pointingHandCursor()
                    .controlSize(.small)
            }
            content
            Spacer(minLength: 0)
        }
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
