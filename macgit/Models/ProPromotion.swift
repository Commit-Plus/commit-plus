// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import FirebaseFirestore

struct ProPromotion: Identifiable {
    enum Frequency: String {
        case once
        case everyday
        case newVersion = "new-version"
    }

    let id: String
    let title: String
    let description: String
    let code: String
    let save: Int
    let endAt: Date?
    let frequency: Frequency
    let audience: AccountPlanAudience

    init?(data: [String: Any]) {
        guard data["enabled"] as? Bool == true,
              let id = data["id"] as? String, !id.isEmpty,
              let title = data["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let description = data["description"] as? String,
              let code = data["code"] as? String, !code.isEmpty,
              let save = data["save"] as? Int, (1...100).contains(save),
              let rawFrequency = data["frequency"] as? String,
              let frequency = Frequency(rawValue: rawFrequency),
              let audience = AccountPlanAudience(configuration: data["showFor"]) else { return nil }
        if let value = data["endAt"], !(value is NSNull) {
            guard let timestamp = value as? Timestamp else { return nil }
            endAt = timestamp.dateValue()
        } else {
            endAt = nil
        }
        self.id = id
        self.title = title
        self.description = description
        self.code = code
        self.save = save
        self.frequency = frequency
        self.audience = audience
    }

    func isEligible(
        defaults: UserDefaults,
        now: Date,
        version: String,
        ignoresFrequency: Bool = false
    ) -> Bool {
        guard endAt.map({ $0 > now }) ?? true else { return false }
        if ignoresFrequency { return true }

        let key = "proPromotion.\(id)"
        switch frequency {
        case .once:
            return defaults.object(forKey: key + ".date") == nil
        case .everyday:
            guard let last = defaults.object(forKey: key + ".date") as? Date else { return true }
            return !Calendar.current.isDate(last, inSameDayAs: now)
        case .newVersion:
            return defaults.string(forKey: key + ".version") != version
        }
    }
}
