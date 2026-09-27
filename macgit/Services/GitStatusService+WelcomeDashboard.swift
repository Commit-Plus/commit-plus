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

extension GitStatusService {
    /// Reads local objects, configuration, index, and cached tracking refs only. Never fetches.
    func welcomeActivity(
        for repository: RecentRepository,
        days: [Date],
        calendar: Calendar = .current
    ) async throws -> WelcomeRepositoryActivity {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_NO_LAZY_FETCH"] = "1"
        var activity = WelcomeRepositoryActivity(
            url: repository.url, name: repository.name,
            commitsByDay: days.map { _ in [] }
        )
        do {
            _ = try await runGit(arguments: ["rev-parse", "--git-dir"], in: repository.url, environment: environment)
        } catch {
            try Task.checkCancellation()
            activity.activityNote = "Repository unavailable. Check its local folder."
            return activity
        }
        try Task.checkCancellation()
        let email = (try? await runGit(arguments: ["config", "user.email"], in: repository.url, environment: environment))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !email.isEmpty else {
            activity.activityNote = "Set Git user.email in this repository to see your activity."
            return activity
        }
        guard let firstDay = days.first else { return activity }
        do {
            let log = try await runGitBounded(
                arguments: ["log", "--all", "--ignore-missing", "HEAD", "--since-as-filter=@\(Int(firstDay.timeIntervalSince1970))",
                            "--no-show-signature", "--format=%H%x09%ae%x09%ct", "--no-patch"],
                in: repository.url, environment: environment,
                outputByteLimit: 2 * 1024 * 1024
            )
            activity.commitsByDay = Self.welcomeCommitBuckets(
                log: log.text, email: email, days: days, calendar: calendar
            )
            if log.isTruncated {
                activity.activityNote = "Large history: activity is partial."
            }
        } catch {
            try Task.checkCancellation()
            activity.activityNote = "Commit activity could not be read."
        }
        return activity
    }

    /// Compare literal author emails, never a regular expression.
    static func welcomeCommitBuckets(
        log: String, email: String, days: [Date], calendar: Calendar
    ) -> [Set<String>] {
        var buckets = days.map { _ in Set<String>() }
        let expectedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for line in log.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  fields[1].lowercased() == expectedEmail,
                  let timestamp = TimeInterval(fields[2]) else { continue }
            let date = calendar.startOfDay(for: Date(timeIntervalSince1970: timestamp))
            guard let index = days.firstIndex(of: date) else { continue }
            buckets[index].insert(String(fields[0]))
        }
        return buckets
    }
}
