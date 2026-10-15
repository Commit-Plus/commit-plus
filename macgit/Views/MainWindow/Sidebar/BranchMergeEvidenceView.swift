// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import SwiftUI

struct BranchMergeEvidenceView: View {
    let assessment: BranchMergeAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Fully Merged", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(assessment.branch).font(.subheadline).fontWeight(.medium)
            Text(assessment.detail).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(assessment.evidence.enumerated()), id: \.offset) { _, evidence in
                if let url = evidence.webURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label(evidence.title, systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                } else {
                    Label(evidence.title, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                }
                if let target = evidence.targetBranch {
                    Text("Target: \(target)").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text("Checked \(assessment.checkedAt.formatted(date: .abbreviated, time: .shortened)) · tip \(assessment.tipSHA.prefix(8))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

