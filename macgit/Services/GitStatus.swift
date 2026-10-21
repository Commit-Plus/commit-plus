//
//  GitStatus.swift
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

nonisolated enum FileStatus: String, CaseIterable, Sendable {
    case modified
    case staged
    case untracked
    case deleted
    case renamed
    case added
    case conflict

    var displayColor: String {
        switch self {
        case .staged, .added:
            return "green"
        case .modified, .deleted:
            return "red"
        case .untracked:
            return "grey"
        case .renamed:
            return "green"
        case .conflict:
            return "red"
        }
    }
}

nonisolated struct StatusFile: Identifiable, Equatable, Hashable, Sendable {
    let path: String
    let status: FileStatus
    let originalPath: String?

    // Status refreshes recreate these values. Keep identity stable so a large
    // untracked tree is diffed in place instead of being removed and rebuilt.
    var id: String {
        "\(status.rawValue):\(path):\(originalPath ?? "")"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var directory: String {
        let url = URL(fileURLWithPath: path)
        return url.deletingLastPathComponent().path
    }

    var fileExtension: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff", "tif", "ico", "heic", "heif", "raw", "cr2", "nef", "arw", "dng"].contains(fileExtension)
    }

    var isVideo: Bool {
        ["mp4", "mov", "mkv", "avi", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp"].contains(fileExtension)
    }

    var isBinary: Bool {
        let binaryExtensions = [
            // Archives
            "zip", "tar", "gz", "bz2", "7z", "rar", "xz", "lz4", "zst",
            // Documents
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf",
            // Executables / Packages
            "exe", "dll", "dmg", "pkg", "deb", "rpm", "apk", "ipa", "app", "msi",
            "so", "dylib", "a", "o", "class", "jar", "war", "ear",
            // Disk / ISO
            "iso", "img", "vmdk", "vhd",
            // Databases
            "db", "sqlite", "sqlite3", "mdb", "accdb",
            // Ebooks
            "mobi", "epub", "azw", "azw3",
            // Adobe / Design
            "psd", "ai", "indd", "sketch", "fig", "xd",
            // Audio
            "mp3", "aac", "ogg", "flac", "wav", "m4a", "wma", "aiff",
            // Video
            "mp4", "avi", "mov", "mkv", "flv", "wmv", "webm", "m4v", "mpg", "mpeg", "3gp",
            // Fonts
            "otf", "ttf", "woff", "woff2", "eot",
            // Other binary
            "bin", "dat", "cache", "pdb", "mo", "po", "nib", "strings"
        ]
        return binaryExtensions.contains(fileExtension)
    }
}

nonisolated struct GitStatus: Equatable, Sendable {
    let staged: [StatusFile]
    let unstaged: [StatusFile]
    let untracked: [StatusFile]

    var isEmpty: Bool {
        staged.isEmpty && unstaged.isEmpty && untracked.isEmpty
    }
}

nonisolated struct GitStatusSnapshot: Sendable {
    let status: GitStatus
    /// Space-joined object IDs from porcelain v2, keyed by path: HEAD and index
    /// blobs for tracked changes, the conflict stages for unmerged paths.
    /// Untracked paths have no entry.
    let objectIDs: [String: String]
}
