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

struct OrphanedUndoBackupReport: Sendable {
    let directories: [URL]
    let byteCount: Int64

    var count: Int { directories.count }
}

actor AdvancedMaintenanceService {
    static let shared = AdvancedMaintenanceService()

    private let fileManager: FileManager
    private let snapshotRegistry: GitUndoSnapshotRegistry

    init(
        fileManager: FileManager = .default,
        snapshotRegistry: GitUndoSnapshotRegistry = .shared
    ) {
        self.fileManager = fileManager
        self.snapshotRegistry = snapshotRegistry
    }

    func orphanedUndoBackups(in repositories: [URL]) -> OrphanedUndoBackupReport {
        var directories: [URL] = []
        var byteCount: Int64 = 0
        let snapshotStore = GitFileUndoSnapshotStore()

        for repositoryURL in Set(repositories.map(\.standardizedFileURL)) {
            guard let root = try? snapshotStore.undoRoot(in: repositoryURL) else {
                continue
            }
            guard let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for directory in children {
                guard let snapshotID = UUID(uuidString: directory.lastPathComponent),
                      !snapshotRegistry.contains(snapshotID),
                      (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory)
                        == true else {
                    continue
                }
                directories.append(directory)
                byteCount += directorySize(directory)
            }
        }

        return OrphanedUndoBackupReport(
            directories: directories,
            byteCount: byteCount
        )
    }

    func remove(_ report: OrphanedUndoBackupReport) throws {
        for directory in report.directories {
            let snapshotID = UUID(uuidString: directory.lastPathComponent)
            guard snapshotID.map({ !snapshotRegistry.contains($0) }) ?? false else {
                continue
            }
            if fileManager.fileExists(atPath: directory.path) {
                try fileManager.removeItem(at: directory)
            }
        }
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            ), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
