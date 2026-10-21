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

struct FileStatusSelectionKey: Hashable {
    let path: String
    let originalPath: String?
    let status: FileStatus
    let isStaged: Bool

    init(file: StatusFile, isStaged: Bool) {
        self.path = file.path
        self.originalPath = file.originalPath
        self.status = file.status
        self.isStaged = isStaged
    }
}

enum FileStatusSelectionSection {
    case staged
    case changed
}

enum FileStatusSelectionAction {
    case stage
    case unstage
    case discard
    case remove
}

struct FileStatusActionSelection {
    let selectedKeys: Set<FileStatusSelectionKey>
    let stagedFiles: [StatusFile]
    let changedFiles: [StatusFile]

    var selectedStagedFiles: [StatusFile] {
        selectedFiles(from: stagedFiles, isStaged: true)
    }

    var selectedChangedFiles: [StatusFile] {
        selectedFiles(from: changedFiles, isStaged: false)
    }

    var selectedFiles: [StatusFile] {
        selectedStagedFiles + selectedChangedFiles
    }

    var prunedSelection: Set<FileStatusSelectionKey> {
        selectedKeys.intersection(currentSelectionKeys)
    }

    var isSingleFileActionDisabled: Bool {
        selectedKeys.count > 1
    }

    func title(for section: FileStatusSelectionSection) -> String {
        switch section {
        case .staged:
            return hasSelectedFiles(isStaged: true) ? "Unstage selected" : "Unstage All"
        case .changed:
            return hasSelectedFiles(isStaged: false) ? "Stage selected" : "Stage All"
        }
    }

    func title(for action: FileStatusSelectionAction) -> String {
        switch action {
        case .stage:
            return isSingleFileActionDisabled && hasSelectedFiles(isStaged: false) ? "Stage selected" : "Stage"
        case .unstage:
            return isSingleFileActionDisabled && hasSelectedFiles(isStaged: true) ? "Unstage selected" : "Unstage"
        case .discard:
            return isSingleFileActionDisabled && hasSelectedFiles(isStaged: false) ? "Discard selected" : "Discard"
        case .remove:
            return isSingleFileActionDisabled ? "Remove selected" : "Remove"
        }
    }

    func files(for action: FileStatusSelectionAction, fallback: StatusFile) -> [StatusFile] {
        switch action {
        case .stage:
            return selectedActionFiles(selectedChangedFiles, fallback: fallback)
        case .unstage:
            return selectedActionFiles(selectedStagedFiles, fallback: fallback)
        case .discard:
            return selectedActionFiles(selectedChangedFiles, fallback: fallback)
        case .remove:
            return selectedActionFiles(uniqueFilesByPath(selectedFiles), fallback: fallback)
        }
    }

    func dragPaths(startingAt file: StatusFile, isStaged: Bool) -> [String] {
        let startingKey = FileStatusSelectionKey(file: file, isStaged: isStaged)
        let sourceFiles: [StatusFile]
        if selectedKeys.contains(startingKey) {
            sourceFiles = uniqueFilesByPath(selectedFiles)
        } else {
            sourceFiles = [file]
        }

        var seen: Set<String> = []
        var paths: [String] = []
        for source in sourceFiles {
            for path in [source.originalPath, source.path] {
                guard let path, !path.isEmpty, seen.insert(path).inserted else { continue }
                paths.append(path)
            }
        }
        return paths
    }

    func filesForDrop(paths: [String], into section: FileStatusSelectionSection) -> [StatusFile] {
        let draggedPaths = Set(paths.filter { !$0.isEmpty })
        guard !draggedPaths.isEmpty else { return [] }

        let sourceFiles = switch section {
        case .staged:
            changedFiles
        case .changed:
            stagedFiles
        }

        return sourceFiles.filter { file in
            draggedPaths.contains(file.path)
                || file.originalPath.map(draggedPaths.contains) == true
        }
    }

    private var currentSelectionKeys: Set<FileStatusSelectionKey> {
        Set(stagedFiles.map { FileStatusSelectionKey(file: $0, isStaged: true) })
            .union(changedFiles.map { FileStatusSelectionKey(file: $0, isStaged: false) })
    }

    private func selectedFiles(from files: [StatusFile], isStaged: Bool) -> [StatusFile] {
        files.filter { selectedKeys.contains(FileStatusSelectionKey(file: $0, isStaged: isStaged)) }
    }

    private func hasSelectedFiles(isStaged: Bool) -> Bool {
        selectedKeys.contains { $0.isStaged == isStaged }
    }

    private func selectedActionFiles(_ files: [StatusFile], fallback: StatusFile) -> [StatusFile] {
        if isSingleFileActionDisabled && !files.isEmpty {
            return files
        }
        return [fallback]
    }

    private func uniqueFilesByPath(_ files: [StatusFile]) -> [StatusFile] {
        var seenPaths: Set<String> = []
        return files.filter { file in
            seenPaths.insert(file.path).inserted
        }
    }
}
