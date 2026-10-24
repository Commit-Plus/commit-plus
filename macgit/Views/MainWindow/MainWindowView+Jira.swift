// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

extension MainWindowView {
    /// Opens the existing branch or Git Flow start flow with a name suggested from the issue; nothing is written to Jira.
    func prepareCreateBranch(from issue: JiraIssue, target: JiraBranchTarget) {
        let name = JiraBranchNameSuggester.name(key: issue.key, summary: issue.summary)
        switch target {
        case .gitFlow(let kind) where gitFlowConfiguration.isEnabled:
            pendingGitFlowInitialTopicName = name
            pendingGitFlowTopicKind = kind
        case .gitFlow, .plainBranch:
            branchSheetPresentation = BranchSheetPresentation(startPoint: nil, initialBranchName: name)
        }
    }
}
