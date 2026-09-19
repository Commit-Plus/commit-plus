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

protocol GitSubtreeRegistryProtocol {
    func entries(in repositoryURL: URL) async throws -> [GitSubtreeEntry]
    func save(_ entry: GitSubtreeEntry, in repositoryURL: URL) async throws
    func remove(id: String, in repositoryURL: URL) async throws
}

enum GitSubtreeRegistryError: LocalizedError, Equatable {
    case emptyName
    case emptyRepository
    case invalidLocalRepository
    case emptyBranch
    case emptyPath
    case absolutePath
    case pathOutsideRepository
    case prefixAlreadyExists(String)
    case duplicatePath(String)
    case overlappingPath(String)
    case emptyID

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Enter a subtree name."
        case .emptyRepository:
            "Enter a subtree repository URL."
        case .invalidLocalRepository:
            "The selected local folder is not a Git repository."
        case .emptyBranch:
            "Enter a branch name."
        case .emptyPath:
            "Choose a path inside this repository."
        case .absolutePath:
            "The subtree path must be relative to this repository."
        case .pathOutsideRepository:
            "The subtree path must stay inside this repository."
        case let .prefixAlreadyExists(path):
            "A folder already exists at \(path). Delete it or choose another path."
        case let .duplicatePath(path):
            "A subtree is already linked at \(path)."
        case let .overlappingPath(path):
            "A subtree path already overlaps \(path)."
        case .emptyID:
            "The subtree entry is missing an identifier."
        }
    }
}

actor GitSubtreeRegistry: GitSubtreeRegistryProtocol {
    private let runner: any GitCommandRunning

    init(runner: (any GitCommandRunning)? = nil) {
        self.runner = runner ?? GitStatusService.shared
    }

    func entries(in repositoryURL: URL) async throws -> [GitSubtreeEntry] {
        let output: String
        do {
            output = try await runner.runGit(
                arguments: ["config", "--local", "--null", "--get-regexp", #"^commitplus-subtree\."#],
                in: repositoryURL
            )
        } catch GitError.commandFailed(let message) where message.isEmpty {
            return []
        } catch GitError.commandFailed(let message) where message.contains("No such section") {
            return []
        } catch {
            return []
        }

        let rawRecords = output.data(using: .utf8)?.split(separator: 0) ?? []
        var valuesByID: [String: [String: String]] = [:]
        for record in rawRecords {
            guard let separator = record.firstIndex(of: 0x0A),
                  let key = String(data: record[..<separator], encoding: .utf8),
                  let value = String(data: record[record.index(after: separator)...], encoding: .utf8)
            else {
                continue
            }

            let keyParts = key.split(separator: ".", maxSplits: 2).map(String.init)
            guard keyParts.count == 3,
                  keyParts[0] == "commitplus-subtree" else {
                continue
            }
            valuesByID[keyParts[1], default: [:]][keyParts[2]] = value
        }

        return valuesByID.compactMap { id, values in
            guard let name = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let path = values["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let repository = values["repository"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let branch = values["branch"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  !path.isEmpty,
                  !repository.isEmpty,
                  !branch.isEmpty
            else {
                return nil
            }

            return GitSubtreeEntry(
                id: id,
                name: name,
                path: path.replacingOccurrences(of: "\\", with: "/"),
                repository: repository,
                branch: branch,
                squash: GitSubtreeRegistry.boolValue(values["squash"]),
                folderExists: GitSubtreeRegistry.folderExists(path: path, in: repositoryURL)
            )
        }
        .sorted { left, right in
            left.path.localizedStandardCompare(right.path) == .orderedAscending
        }
    }

    func makeEntry(
        name: String,
        path: String,
        repository: String,
        branch: String,
        squash: Bool,
        in repositoryURL: URL
    ) async throws -> GitSubtreeEntry {
        let normalizedPath = try Self.normalizedRelativePath(path, in: repositoryURL)
        let existingIDs = Set(try await entries(in: repositoryURL).map(\.id))
        return GitSubtreeEntry(
            id: Self.uniqueID(for: normalizedPath, existingIDs: existingIDs),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            path: normalizedPath,
            repository: repository.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            squash: squash,
            folderExists: Self.folderExists(path: normalizedPath, in: repositoryURL)
        )
    }

    func save(_ entry: GitSubtreeEntry, in repositoryURL: URL) async throws {
        let normalized = try await validated(entry, in: repositoryURL)
        let keyPrefix = "commitplus-subtree.\(normalized.id)"
        let values = [
            ("name", normalized.name),
            ("path", normalized.path),
            ("repository", normalized.repository),
            ("branch", normalized.branch),
            ("squash", normalized.squash ? "true" : "false")
        ]

        for (key, value) in values {
            _ = try await runner.runGit(
                arguments: ["config", "--local", "\(keyPrefix).\(key)", value],
                in: repositoryURL
            )
        }
    }

    func remove(id: String, in repositoryURL: URL) async throws {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw GitSubtreeRegistryError.emptyID
        }
        _ = try? await runner.runGit(
            arguments: ["config", "--local", "--remove-section", "commitplus-subtree.\(id)"],
            in: repositoryURL
        )
    }

    private func validated(_ entry: GitSubtreeEntry, in repositoryURL: URL) async throws -> GitSubtreeEntry {
        let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw GitSubtreeRegistryError.emptyID
        }

        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw GitSubtreeRegistryError.emptyName
        }

        let repository = entry.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw GitSubtreeRegistryError.emptyRepository
        }

        let branch = entry.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            throw GitSubtreeRegistryError.emptyBranch
        }

        let path = try Self.normalizedRelativePath(entry.path, in: repositoryURL)
        let existing = try await entries(in: repositoryURL).filter { $0.id != id }
        try Self.rejectPathConflict(path, existing: existing)

        return GitSubtreeEntry(
            id: id,
            name: name,
            path: path,
            repository: repository,
            branch: branch,
            squash: entry.squash,
            folderExists: Self.folderExists(path: path, in: repositoryURL)
        )
    }

    static func uniqueID(for path: String, existingIDs: Set<String>) -> String {
        let base = slug(for: path).isEmpty ? "subtree" : slug(for: path)
        var candidate = base
        var suffix = 2
        while existingIDs.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    static func normalizedRelativePath(_ rawPath: String, in repositoryURL: URL) throws -> String {
        let rawPath = rawPath
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !rawPath.isEmpty else {
            throw GitSubtreeRegistryError.emptyPath
        }
        guard !NSString(string: rawPath).isAbsolutePath else {
            throw GitSubtreeRegistryError.absolutePath
        }

        let lexicalRepositoryURL = repositoryURL.standardizedFileURL
        let lexicalCandidateURL = lexicalRepositoryURL
            .appendingPathComponent(rawPath)
            .standardizedFileURL
        guard lexicalCandidateURL != lexicalRepositoryURL,
              lexicalCandidateURL.pathComponents.starts(with: lexicalRepositoryURL.pathComponents) else {
            throw GitSubtreeRegistryError.pathOutsideRepository
        }

        let relativeComponents = lexicalCandidateURL.pathComponents
            .dropFirst(lexicalRepositoryURL.pathComponents.count)
        let path = relativeComponents.joined(separator: "/")
        let standardizedRepositoryURL = lexicalRepositoryURL.resolvingSymlinksInPath()
        let candidateURL = relativeComponents.reduce(standardizedRepositoryURL) { currentURL, component in
            currentURL
                .appendingPathComponent(component)
                .resolvingSymlinksInPath()
        }
        guard candidateURL != standardizedRepositoryURL,
              candidateURL.pathComponents.starts(with: standardizedRepositoryURL.pathComponents) else {
            throw GitSubtreeRegistryError.pathOutsideRepository
        }
        return path
    }

    static func rejectPathConflict(_ path: String, existing: [GitSubtreeEntry]) throws {
        for entry in existing {
            if entry.path == path {
                throw GitSubtreeRegistryError.duplicatePath(path)
            }
            if entry.path.hasPrefix(path + "/") || path.hasPrefix(entry.path + "/") {
                throw GitSubtreeRegistryError.overlappingPath(entry.path)
            }
        }
    }

    private static func folderExists(path: String, in repositoryURL: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: repositoryURL.appendingPathComponent(path, isDirectory: true).path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private static func boolValue(_ rawValue: String?) -> Bool {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1", "on":
            true
        default:
            false
        }
    }

    private static func slug(for path: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = path.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

