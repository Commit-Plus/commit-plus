// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

struct RepositoryContributorsSheet: View {
    let contributors: [RepositoryStatistics.Count]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("All contributors", systemImage: "person.2").font(.title2.weight(.semibold))
                Text(contributors.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
            }.padding(20)
            Divider()
            List(contributors) { contributor in
                HStack(spacing: 16) {
                    Text(contributor.key).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 12)
                    Text(contributor.count.formatted()).monospacedDigit().fontWeight(.medium)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(contributor.key), \(contributor.count) commits")
            }.listStyle(.inset)
            Divider()
            HStack {
                Text("Commits in the selected period").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 560, height: 500)
    }
}
