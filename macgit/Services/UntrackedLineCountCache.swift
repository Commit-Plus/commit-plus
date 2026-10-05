// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

actor UntrackedLineCountCache {
    static let shared = UntrackedLineCountCache()

    private struct Signature: Equatable {
        let size: UInt64
        let modified: Date
        let inode: UInt64
    }

    private struct Entry {
        let signature: Signature
        let count: FileLineChangeCount?
    }

    private var entries: [URL: Entry] = [:]
    private let capacity = 2_000

    func counts(for files: [StatusFile], in repositoryURL: URL) throws -> [String: FileLineChangeCount] {
        var result: [String: FileLineChangeCount] = [:]
        for file in files {
            try Task.checkCancellation()
            let url = repositoryURL.appendingPathComponent(file.path).standardizedFileURL
            guard let signature = signature(for: url) else {
                entries.removeValue(forKey: url)
                continue
            }
            if let cached = entries[url], cached.signature == signature {
                result[file.path] = cached.count
                continue
            }
            let count: FileLineChangeCount?
            do {
                count = try countLines(at: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                entries.removeValue(forKey: url)
                continue
            }
            // AI may still be writing the file. Publish only a stable read.
            guard self.signature(for: url) == signature else { continue }
            if entries.count >= capacity { entries.removeAll(keepingCapacity: true) }
            entries[url] = Entry(signature: signature, count: count)
            result[file.path] = count
        }
        return result
    }

    private func signature(for url: URL) -> Signature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return Signature(size: size.uint64Value, modified: modified, inode: inode.uint64Value)
    }

    private func countLines(at url: URL) throws -> FileLineChangeCount? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var newlines = 0
        var lastByte: UInt8?
        while true {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty else { break }
            // Match Git's binary marker without decoding or retaining the file.
            guard !chunk.contains(0) else { return nil }
            newlines += chunk.count { $0 == 10 }
            lastByte = chunk.last
        }
        return FileLineChangeCount(added: newlines + (lastByte == nil || lastByte == 10 ? 0 : 1), removed: 0)
    }
}
