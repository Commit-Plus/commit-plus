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

@MainActor
final class ReleaseNotesPresentationStore {
    static let shared = ReleaseNotesPresentationStore()

    private let defaults: UserDefaults
    private let versionProvider: () -> String?
    private let changelogURLProvider: () -> URL?
    private let markdownLoader: (URL) async throws -> String
    private let lastPresentedVersionKey = "releaseNotes.lastPresentedVersion"
    private var versionsInFlight = Set<String>()

    init(
        defaults: UserDefaults = .standard,
        versionProvider: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        changelogURLProvider: @escaping () -> URL? = {
            guard let value = Bundle.main.object(forInfoDictionaryKey: "CommitPlusChangelogURL") as? String else {
                return nil
            }
            return URL(string: value)
        },
        markdownLoader: @escaping (URL) async throws -> String = { url in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let markdown = String(data: data, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            return markdown
        }
    ) {
        self.defaults = defaults
        self.versionProvider = versionProvider
        self.changelogURLProvider = changelogURLProvider
        self.markdownLoader = markdownLoader
    }

    func claimPresentation() async -> ReleaseNotesPresentation? {
        guard let version = versionProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              defaults.string(forKey: lastPresentedVersionKey) != version,
              !versionsInFlight.contains(version),
              let changelogURL = changelogURLProvider() else {
            return nil
        }

        versionsInFlight.insert(version)
        defer { versionsInFlight.remove(version) }

        do {
            let markdown = try await markdownLoader(changelogURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { return nil }

            defaults.set(version, forKey: lastPresentedVersionKey)
            return ReleaseNotesPresentation(version: version, markdown: markdown)
        } catch {
            return nil
        }
    }
}
