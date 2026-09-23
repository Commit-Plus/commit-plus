// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

nonisolated enum GitLFSProgressReader {
    static func observe(file: URL, update: @escaping @Sendable (GitLFSTransferProgress) -> Void) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return }
            defer { try? handle.close() }
            var pending = Data()
            while !Task.isCancelled {
                if let data = try? handle.read(upToCount: 65_536), !data.isEmpty {
                    pending.append(data)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending[..<newline], as: UTF8.self)
                        pending.removeSubrange(...newline)
                        if let progress = GitLFSTransferProgress(line) { update(progress) }
                    }
                    if pending.count > 65_536 { pending.removeAll() }
                }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
}
