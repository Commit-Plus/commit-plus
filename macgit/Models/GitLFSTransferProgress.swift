// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated struct GitLFSTransferProgress: Equatable, Sendable {
    let direction: String
    let fileIndex: Int
    let fileCount: Int
    let bytes: Int64
    let totalBytes: Int64
    let name: String

    init?(_ line: String) {
        let fields = line.split(separator: " ", maxSplits: 3)
        guard fields.count == 4, ["download", "upload", "checkout"].contains(fields[0]) else { return nil }
        let files = fields[1].split(separator: "/")
        let sizes = fields[2].split(separator: "/")
        guard files.count == 2, sizes.count == 2, let index = Int(files[0]), let count = Int(files[1]),
              let bytes = Int64(sizes[0]), let total = Int64(sizes[1]), index > 0, count >= index,
              bytes >= 0, total > 0, bytes <= total else { return nil }
        direction = String(fields[0])
        fileIndex = index
        fileCount = count
        self.bytes = bytes
        totalBytes = total
        name = String(fields[3])
    }
}
