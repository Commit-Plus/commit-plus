// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

extension MainWindowView {
    /// Opens the existing branch or Git Flow start flow with a name suggested from an issue;
    /// nothing is written to the issue tracker.
    func prepareCreateBranch(key: String, summary: String, target: IssueBranchTarget) {
        let name = IssueBranchNameSuggester.name(key: key, summary: summary)
        switch target {
        case .gitFlow(let kind) where gitFlowConfiguration.isEnabled:
            pendingGitFlowStart = GitFlowStartPresentation(kind: kind, initialTopicName: name)
        case .gitFlow, .plainBranch:
            branchSheetPresentation = BranchSheetPresentation(startPoint: nil, initialBranchName: name)
        }
    }
}
