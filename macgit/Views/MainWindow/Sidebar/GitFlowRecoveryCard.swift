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

struct GitFlowRecoveryCard: View {
    @Environment(\.appTextScale) private var textScale
    let checkpoint: GitFlowFinishCheckpoint?
    let issue: GitFlowLocalStateIssue?
    let actionsEnabled: Bool
    let onResume: () -> Void
    let onAbort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let checkpoint {
                Label("Finish paused", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .bold()
                Text("\(checkpoint.plan.kind.displayName): \(checkpoint.plan.sourceBranch)")
                    .lineLimit(2)
                Text(checkpoint.phase.recoveryDescription)
                    .foregroundStyle(.secondary)
                Text(checkpoint.phase.recoveryGuidance)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Resume", action: onResume)
                        .disabled(!actionsEnabled)
                        .accessibilityHint("Continues the paused Git Flow finish after conflicts are resolved.")
                    Button("Abort", role: .destructive, action: onAbort)
                        .disabled(!actionsEnabled)
                        .accessibilityHint("Aborts the paused Git Flow finish and restores guarded refs.")
                }
            } else if let issue {
                Label("Recovery state unavailable", systemImage: "exclamationmark.triangle.fill")
                    .bold()
                Text(issue.message)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.scaled(by: textScale))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Git Flow recovery")
    }
}

private extension GitFlowFinishCheckpoint.Phase {
    var recoveryDescription: String {
        switch self {
        case .primaryMerge:
            return "Step: merge into Main or the primary target"
        case .secondaryMerge:
            return "Step: merge into Develop"
        case .topicRebase:
            return "Step: rebase the topic branch"
        case .topicFastForward:
            return "Step: fast-forward Develop"
        }
    }

    var recoveryGuidance: String {
        switch self {
        case .primaryMerge, .secondaryMerge, .topicRebase:
            return "If Git reports conflicts, resolve them in File Status before Resume."
        case .topicFastForward:
            return "Resume to continue the recorded fast-forward step."
        }
    }
}
