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

import SwiftUI
import CryptoKit

struct ReflogActorAvatar: View {
    let name: String
    let email: String
    var size: CGFloat = 36

    var body: some View {
        AsyncImage(url: avatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay {
                        if initials.isEmpty {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(initials)
                                .font(size < 30 ? .system(size: size * 0.42, weight: .semibold) : .callout.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                    }
            }
        }
        .id(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var avatarURL: URL? {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else { return nil }
        let hash = SHA256.hash(data: Data(normalizedEmail.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://gravatar.com/avatar/\(hash)?s=96&d=404")
    }
}
