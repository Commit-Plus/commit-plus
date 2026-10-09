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

import Combine
import Foundation

@MainActor
final class AdvancedSettingsStore: ObservableObject {
    static let shared = AdvancedSettingsStore()

    static let verboseGitLoggingKey = "advanced.verboseGitLogging"
    private static let historyLoadSizeKey = "advanced.historyLoadSize"
    private static let diffSyntaxHighlightingKey = "advanced.diffSyntaxHighlighting"

    @Published var verboseGitLogging: Bool {
        didSet {
            userDefaults.set(verboseGitLogging, forKey: Self.verboseGitLoggingKey)
        }
    }

    @Published var historyLoadSize: HistoryLoadSize {
        didSet {
            userDefaults.set(historyLoadSize.rawValue, forKey: Self.historyLoadSizeKey)
        }
    }

    @Published var diffSyntaxHighlighting: Bool {
        didSet {
            userDefaults.set(diffSyntaxHighlighting, forKey: Self.diffSyntaxHighlightingKey)
        }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        verboseGitLogging =
            userDefaults.object(forKey: Self.verboseGitLoggingKey) as? Bool ?? false
        let storedHistoryLoadSize =
            userDefaults.object(forKey: Self.historyLoadSizeKey) as? Int
        historyLoadSize = storedHistoryLoadSize
            .flatMap(HistoryLoadSize.init(rawValue:)) ?? .balanced
        diffSyntaxHighlighting =
            userDefaults.object(forKey: Self.diffSyntaxHighlightingKey) as? Bool ?? false
    }

    func restoreDefaults() {
        verboseGitLogging = false
        historyLoadSize = .balanced
        diffSyntaxHighlighting = false
    }
}
