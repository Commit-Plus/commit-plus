// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum GitCredentialHelperMode: Hashable, Identifiable, Sendable {
    case commitPlusAccountsOnly
    case helper(String)
    case preserveExisting

    var id: String {
        switch self {
        case .commitPlusAccountsOnly:
            "commit-plus-accounts-only"
        case .helper(let name):
            "helper:\(name)"
        case .preserveExisting:
            "preserve-existing"
        }
    }

    static func resolve(configuredValues: [String]) -> Self {
        let effectiveValues = configuredValues.reduce(into: [String]()) { result, value in
            if value.isEmpty {
                result.removeAll()
            } else {
                result.append(value)
            }
        }

        switch effectiveValues.count {
        case 0:
            return .commitPlusAccountsOnly
        case 1:
            return .helper(effectiveValues[0])
        default:
            return .preserveExisting
        }
    }
}
