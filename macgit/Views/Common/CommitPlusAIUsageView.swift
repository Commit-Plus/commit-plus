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

struct CommitPlusAIUsageView: View {
    @ObservedObject var controller: CommitPlusAIUsageController
    var body: some View {
        Section {
            Text("Included with Pro")
                .font(.headline)
            switch controller.state {
            case .idle, .loading:
                ProgressView("Loading AI usage…")
            case .unavailable:
                LabeledContent("Usage", value: "Usage unavailable")
                Button("Retry") { Task { await controller.refresh(force: true) } }
            case .loaded(let allowance):
                LabeledContent("Available credits", value: "\(allowance.creditLabel) / \(allowance.allowanceLabel)")
                ProgressView(value: Double(allowance.availableUnits), total: Double(max(1, allowance.allowanceUnits)))
                    .accessibilityLabel("Available AI credits")
                    .accessibilityValue(allowance.creditLabel)
                if let reset = allowance.resetsAt {
                    LabeledContent("Renews", value: reset.formatted(date: .abbreviated, time: .shortened))
                } else { Text("No further credit renewal is currently scheduled.").foregroundStyle(.secondary) }
                if allowance.availableUnits == 0 { Text(allowance.availability.detail).foregroundStyle(.secondary) }
                if allowance.accountingPending { Text("Available credits account for requests still being processed.").foregroundStyle(.secondary) }
            }
        } header: {
            Label("Commit+ AI", systemImage: "sparkles")
        } footer: {
            Text("Relevant repository content is sent to a cloud AI service to process your request. Unused credits expire at the end of each monthly period.")
        }
    }
}
