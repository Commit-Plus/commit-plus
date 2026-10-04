// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Small local snapshot, scoped to the account and never synced to Commit+ Cloud.
@MainActor
struct CommitPlusAIAllowanceCache {
    struct Snapshot: Codable {
        let allowance: CommitPlusAIAllowance
        let updatedAt: Date
    }

    let defaults: UserDefaults
    private func key(for uid: String) -> String { "dev.thanhtran.macgit.aiAllowance.v1.\(uid)" }

    func load(for uid: String, now: Date, duration: TimeInterval) -> Snapshot? {
        guard let data = defaults.data(forKey: key(for: uid)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        let age = now.timeIntervalSince(snapshot.updatedAt)
        guard age >= 0, age < duration, now < snapshot.allowance.periodEnd else { return nil }
        return snapshot
    }

    func save(_ allowance: CommitPlusAIAllowance, for uid: String, at date: Date) {
        guard let data = try? JSONEncoder().encode(Snapshot(allowance: allowance, updatedAt: date)) else { return }
        defaults.set(data, forKey: key(for: uid))
    }
}
