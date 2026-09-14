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

nonisolated struct CommitPlusAIAllowance: Decodable, Equatable, Sendable {
    let periodID: String
    let periodStart: Date
    let periodEnd: Date
    let resetsAt: Date?
    let allowanceUnits: Int64
    let consumedUnits: Int64
    let reservedUnits: Int64
    let availableUnits: Int64
    let unitsPerCredit: Int64
    let access: String
    let accountingPending: Bool

    private enum CodingKeys: String, CodingKey {
        case periodID, periodStart, periodEnd, resetsAt, allowanceUnits, consumedUnits
        case reservedUnits, availableUnits, unitsPerCredit, access, accountingPending
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        periodID = try c.decode(String.self, forKey: .periodID)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ key: CodingKeys) throws -> Date {
            let value = try c.decode(String.self, forKey: key)
            guard let result = formatter.date(from: value), formatter.string(from: result) == value else { throw CommitPlusAIError.invalidResponse }
            return result
        }
        periodStart = try date(.periodStart)
        periodEnd = try date(.periodEnd)
        resetsAt = try c.decodeNil(forKey: .resetsAt) ? nil : date(.resetsAt)
        allowanceUnits = try c.decode(Int64.self, forKey: .allowanceUnits)
        consumedUnits = try c.decode(Int64.self, forKey: .consumedUnits)
        reservedUnits = try c.decode(Int64.self, forKey: .reservedUnits)
        availableUnits = try c.decode(Int64.self, forKey: .availableUnits)
        unitsPerCredit = try c.decode(Int64.self, forKey: .unitsPerCredit)
        access = try c.decode(String.self, forKey: .access)
        accountingPending = try c.decode(Bool.self, forKey: .accountingPending)
        guard !periodID.isEmpty, periodStart < periodEnd,
              resetsAt == nil || resetsAt == periodEnd,
              [allowanceUnits, consumedUnits, reservedUnits, availableUnits].allSatisfy({ $0 >= 0 && $0 <= 9_007_199_254_740_991 }),
              unitsPerCredit == 1_000_000, ["active", "inactive"].contains(access),
              consumedUnits <= allowanceUnits, reservedUnits <= allowanceUnits - consumedUnits,
              availableUnits == allowanceUnits - consumedUnits - reservedUnits else { throw CommitPlusAIError.invalidResponse }
    }
    var credits: Decimal { Decimal(availableUnits) / Decimal(unitsPerCredit) }
    var creditLabel: String {
        if availableUnits > 0 && availableUnits < 10_000 { return "<0.01" }
        return credits.formatted(.number.precision(.fractionLength(0...2)))
    }
    var allowanceLabel: String { (Decimal(allowanceUnits) / Decimal(unitsPerCredit)).formatted(.number.precision(.fractionLength(0...2))) }
    var availability: AIProviderAvailability {
        if access != "active" { return .unavailable("An active Commit+ Pro subscription is required.") }
        if availableUnits == 0 {
            let renewal = resetsAt.map { " Credits renew on \($0.formatted(date: .abbreviated, time: .shortened))." } ?? " No further credit renewal is currently scheduled."
            return .unavailable("Your AI credits are used up." + renewal)
        }
        return .available
    }
}
