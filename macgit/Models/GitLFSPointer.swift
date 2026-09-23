// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSPointer: Equatable, Sendable {
    let oid: String
    let size: Int64

    init?(_ text: String) {
        guard text.utf8.count <= 1024 else { return nil }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
        guard lines.first == "version https://git-lfs.github.com/spec/v1" else { return nil }
        let oids = lines.filter { $0.hasPrefix("oid sha256:") }
        let sizes = lines.filter { $0.hasPrefix("size ") }
        guard oids.count == 1, sizes.count == 1,
              let size = Int64(sizes[0].dropFirst(5)), size >= 0 else { return nil }
        let oid = String(oids[0].dropFirst(11))
        guard oid.count == 64, oid.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              lines.dropFirst().allSatisfy({ $0.hasPrefix("oid sha256:") || $0.hasPrefix("size ") || $0.hasPrefix("ext-") }) else { return nil }
        self.oid = oid
        self.size = size
    }
}
