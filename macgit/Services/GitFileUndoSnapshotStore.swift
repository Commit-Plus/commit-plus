//
//  GitFileUndoSnapshotStore.swift
//  macgit
//

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

struct GitFileUndoSnapshotStore {
    private let fileManager = FileManager.default

    func capture(paths: [String], in repositoryURL: URL) throws -> GitFileUndoSnapshot {
        let snapshotID = UUID()
        let directory = try snapshotDirectory(snapshotID, in: repositoryURL)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let items = try paths.map { path in
            let source = repositoryURL.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: source.path) else {
                return GitFileUndoSnapshotItem(path: path, existed: false, backupRelativePath: nil)
            }

            let backupRelativePath = "files/\(path)"
            let backupURL = directory.appendingPathComponent(backupRelativePath)
            try fileManager.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: source, to: backupURL)
            return GitFileUndoSnapshotItem(path: path, existed: true, backupRelativePath: backupRelativePath)
        }

        let snapshot = GitFileUndoSnapshot(id: snapshotID, items: items)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: manifestURL(snapshotID, in: repositoryURL), options: .atomic)
        GitUndoSnapshotRegistry.shared.register(snapshotID)
        return snapshot
    }

    func restore(snapshotID: UUID, in repositoryURL: URL) throws {
        let data = try Data(contentsOf: manifestURL(snapshotID, in: repositoryURL))
        let snapshot = try JSONDecoder().decode(GitFileUndoSnapshot.self, from: data)
        let snapshotDirectory = try snapshotDirectory(snapshotID, in: repositoryURL)

        for item in snapshot.items {
            let destination = repositoryURL.appendingPathComponent(item.path)
            if item.existed, let backupRelativePath = item.backupRelativePath {
                let backup = snapshotDirectory.appendingPathComponent(backupRelativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: backup, to: destination)
            } else if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }
    }

    func delete(snapshotID: UUID, in repositoryURL: URL) throws {
        let directory = try snapshotDirectory(snapshotID, in: repositoryURL)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        GitUndoSnapshotRegistry.shared.unregister(snapshotID)
    }

    func undoRoot(in repositoryURL: URL) throws -> URL {
        try gitDirectory(in: repositoryURL)
            .appendingPathComponent("macgit/undo", isDirectory: true)
    }

    private func gitDirectory(in repositoryURL: URL) throws -> URL {
        let dotGitURL = repositoryURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: dotGitURL.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return dotGitURL.standardizedFileURL
        }

        let contents = try String(contentsOf: dotGitURL, encoding: .utf8)
        let firstLine = contents.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let prefix = "gitdir:"
        guard firstLine.hasPrefix(prefix) else {
            throw GitError.commandFailed("The repository's .git file does not contain a valid gitdir pointer.")
        }

        let path = firstLine.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            throw GitError.commandFailed("The repository's .git file contains an empty gitdir pointer.")
        }

        let gitDirectory = URL(
            fileURLWithPath: path,
            isDirectory: true,
            relativeTo: dotGitURL.deletingLastPathComponent()
        ).standardizedFileURL
        var resolvedIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: gitDirectory.path, isDirectory: &resolvedIsDirectory),
              resolvedIsDirectory.boolValue else {
            throw GitError.commandFailed("The repository's git directory could not be found.")
        }
        return gitDirectory
    }

    private func snapshotDirectory(_ id: UUID, in repositoryURL: URL) throws -> URL {
        try undoRoot(in: repositoryURL).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func manifestURL(_ id: UUID, in repositoryURL: URL) throws -> URL {
        try snapshotDirectory(id, in: repositoryURL).appendingPathComponent("manifest.json")
    }
}
