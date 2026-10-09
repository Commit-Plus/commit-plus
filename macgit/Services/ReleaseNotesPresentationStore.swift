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
    private let releaseURLProvider: (String) -> URL?
    private let releaseLoader: (URL) async throws -> Data
    private let lastPresentedVersionKey = "releaseNotes.lastPresentedVersion"
    private var versionsInFlight = Set<String>()
    private var cachedPresentations: [String: ReleaseNotesPresentation] = [:]

    init(
        defaults: UserDefaults = .standard,
        versionProvider: @escaping () -> String? = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        },
        releaseURLProvider: @escaping (String) -> URL? = { version in
            URL(string: "https://api.github.com/repos/Commit-Plus/commit-plus/releases/tags/")?
                .appendingPathComponent("v\(version)")
        },
        releaseLoader: @escaping (URL) async throws -> Data = { url in
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadRevalidatingCacheData
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            return data
        }
    ) {
        self.defaults = defaults
        self.versionProvider = versionProvider
        self.releaseURLProvider = releaseURLProvider
        self.releaseLoader = releaseLoader
    }

    private struct Release: Decodable {
        let tagName: String
        let body: String?
        let draft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft
        }
    }

    var currentVersion: String? {
        guard let version = versionProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return nil }
        return version
    }

    func claimPresentation() async -> ReleaseNotesPresentation? {
        guard let version = currentVersion,
              defaults.string(forKey: lastPresentedVersionKey) != version,
              !versionsInFlight.contains(version) else {
            return nil
        }

        versionsInFlight.insert(version)
        defer { versionsInFlight.remove(version) }

        guard let presentation = await loadPresentation() else { return nil }
        defaults.set(version, forKey: lastPresentedVersionKey)
        return presentation
    }

    /// Explicit viewing remains available after the startup presentation was seen.
    func loadPresentation() async -> ReleaseNotesPresentation? {
        guard let version = currentVersion else { return nil }
        if let cached = cachedPresentations[version] { return cached }
        guard let releaseURL = releaseURLProvider(version) else { return nil }

        do {
            let data = try await releaseLoader(releaseURL)
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard release.tagName == "v\(version)", !release.draft,
                  let markdown = release.body?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !markdown.isEmpty else { return nil }

            let presentation = ReleaseNotesPresentation(version: version, markdown: markdown)
            cachedPresentations[version] = presentation
            return presentation
        } catch {
            return nil
        }
    }
}
