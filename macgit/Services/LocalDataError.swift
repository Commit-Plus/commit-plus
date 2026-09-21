// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

enum LocalDataError: LocalizedError {
    case notReady
    case invalidLegacyData(String)
    var errorDescription: String? {
        switch self {
        case .notReady: "Local data is still loading."
        case .invalidLegacyData(let key): "Saved data could not be migrated (\(key)). The original data has been retained."
        }
    }
}
