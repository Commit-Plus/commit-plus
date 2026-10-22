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

import Foundation

enum CloudAIProviderSupport {
    static func apiKey(
        for descriptor: AIProviderDescriptor,
        credentialStore: any AIProviderCredentialStore
    ) throws -> String {
        guard let key = try credentialStore.apiKey(for: descriptor.id), !key.isEmpty else {
            throw CommitMessageGenerationError.missingAPIKey(descriptor.displayName)
        }
        return key
    }

    static func availability(
        for descriptor: AIProviderDescriptor,
        credentialStore: any AIProviderCredentialStore
    ) -> AIProviderAvailability {
        do {
            return try credentialStore.apiKey(for: descriptor.id) == nil
                ? .unavailable("Add an API key in Settings → AI.")
                : .available
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    static func validate(
        response: HTTPURLResponse,
        data: Data,
        providerName: String
    ) throws {
        guard (200..<300).contains(response.statusCode) else {
            let message = providerErrorMessage(from: data)
            if response.statusCode == 401 || response.statusCode == 403 {
                throw CommitMessageGenerationError.providerRequestFailed(
                    "\(providerName) rejected the API key. Replace it in Settings → AI."
                )
            }
            throw CommitMessageGenerationError.providerRequestFailed(
                message ?? "\(providerName) request failed (HTTP \(response.statusCode))."
            )
        }
    }

    private static func providerErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }
}
