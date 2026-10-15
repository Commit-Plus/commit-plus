// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

struct BranchMergeHintStore {
    private let defaults: UserDefaults
    private let key = "branchMergeDetection.suppressedHints"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isSuppressed(repositoryURL: URL, branch: String) -> Bool {
        values.contains(identifier(repositoryURL: repositoryURL, branch: branch))
    }

    func setSuppressed(_ suppressed: Bool, repositoryURL: URL, branch: String) {
        var updated = values
        let value = identifier(repositoryURL: repositoryURL, branch: branch)
        if suppressed { updated.insert(value) } else { updated.remove(value) }
        defaults.set(Array(updated).sorted(), forKey: key)
    }

    private var values: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    private func identifier(repositoryURL: URL, branch: String) -> String {
        Data((repositoryURL.standardizedFileURL.path + "\n" + branch).utf8).base64EncodedString()
    }
}

