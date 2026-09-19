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

struct SubmoduleAddRequest: Equatable, Sendable {
    let repository: String
    let path: String
    let branch: String?
    let initializeAfterAdd: Bool
    let shallow: Bool
    let force: Bool

    init(
        repository: String,
        path: String,
        branch: String?,
        initializeAfterAdd: Bool,
        shallow: Bool,
        force: Bool = false
    ) {
        self.repository = repository
        self.path = path
        self.branch = branch
        self.initializeAfterAdd = initializeAfterAdd
        self.shallow = shallow
        self.force = force
    }
}

enum SubmoduleUpdateMode: Equatable, Sendable {
    case recordedCommit
    case remoteCheckout
}

enum SubmoduleRequestValidationError: LocalizedError, Equatable {
    case emptyRepository
    case invalidLocalRepository
    case emptyPath
    case absolutePath
    case pathOutsideRepository
    case duplicatePath(String)
    case nestedInsideSubmodule(path: String, existing: String)
    case ancestorOfSubmodule(path: String, existing: String)
    case staleSubmoduleGitDirectory(path: String, prefix: String)

    var errorDescription: String? {
        switch self {
        case .emptyRepository:
            "Enter a submodule repository URL."
        case .invalidLocalRepository:
            "The selected local folder is not a Git repository."
        case .emptyPath:
            "Choose a path inside this repository."
        case .absolutePath:
            "The submodule path must be relative to this repository."
        case .pathOutsideRepository:
            "The submodule path must stay inside this repository."
        case let .duplicatePath(path):
            "A submodule is already configured at \(path)."
        case let .nestedInsideSubmodule(path, existing):
            "Cannot add a submodule at \(path) because it is inside the active submodule at \(existing)."
        case let .ancestorOfSubmodule(path, existing):
            "Cannot add a submodule at \(path) because it would contain the active submodule at \(existing)."
        case let .staleSubmoduleGitDirectory(path, prefix):
            "Cannot add a submodule at \(path): a leftover submodule git directory from a removed submodule exists at .git/modules/\(prefix). Delete it (after confirming nothing needed remains) and try again."
        }
    }
}

enum SubmoduleRequestValidator {
    static func validate(
        addRequest request: SubmoduleAddRequest,
        in repositoryURL: URL
    ) throws -> SubmoduleAddRequest {
        let repository = request.repository.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repository.isEmpty else {
            throw SubmoduleRequestValidationError.emptyRepository
        }
        if NSString(string: repository).isAbsolutePath {
            let localRepositoryURL = URL(fileURLWithPath: repository).standardizedFileURL
            guard FileManager.default.fileExists(
                atPath: localRepositoryURL.appendingPathComponent(".git").path
            ) else {
                throw SubmoduleRequestValidationError.invalidLocalRepository
            }
        }

        let rawPath = request.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !rawPath.isEmpty else {
            throw SubmoduleRequestValidationError.emptyPath
        }
        guard !NSString(string: rawPath).isAbsolutePath else {
            throw SubmoduleRequestValidationError.absolutePath
        }

        let lexicalRepositoryURL = repositoryURL.standardizedFileURL
        let lexicalCandidateURL = lexicalRepositoryURL
            .appendingPathComponent(rawPath)
            .standardizedFileURL
        guard lexicalCandidateURL != lexicalRepositoryURL,
              lexicalCandidateURL.pathComponents.starts(with: lexicalRepositoryURL.pathComponents) else {
            throw SubmoduleRequestValidationError.pathOutsideRepository
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
            throw SubmoduleRequestValidationError.pathOutsideRepository
        }

        let configured = GitStatusService.shared.configuredSubmodulePaths(in: repositoryURL)
        if configured.contains(path) {
            throw SubmoduleRequestValidationError.duplicatePath(path)
        }
        // `git submodule add` cannot nest inside another submodule's git dir,
        // and `--force` does not bypass that. Reject nested paths up front so
        // the user gets an actionable message instead of a raw git fatal.
        for prefix in ancestorPrefixes(of: path) {
            if configured.contains(prefix) {
                throw SubmoduleRequestValidationError.nestedInsideSubmodule(path: path, existing: prefix)
            }
        }
        if let inner = configured.first(where: { $0.hasPrefix(path + "/") }) {
            throw SubmoduleRequestValidationError.ancestorOfSubmodule(path: path, existing: inner)
        }
        if let modulesDirectory = submoduleModulesDirectory(in: repositoryURL) {
            for prefix in ancestorPrefixes(of: path) {
                var isDirectory: ObjCBool = false
                let candidate = modulesDirectory.appendingPathComponent(prefix)
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    throw SubmoduleRequestValidationError.staleSubmoduleGitDirectory(path: path, prefix: prefix)
                }
            }
        }

        let branch = request.branch?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return SubmoduleAddRequest(
            repository: repository,
            path: path.replacingOccurrences(of: "\\", with: "/"),
            branch: branch?.isEmpty == true ? nil : branch,
            initializeAfterAdd: request.initializeAfterAdd,
            shallow: request.shallow,
            force: request.force
        )
    }

    private static func ancestorPrefixes(of path: String) -> [String] {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return [] }
        return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
    }

    private static func submoduleModulesDirectory(in repositoryURL: URL) -> URL? {
        let dotGit = repositoryURL.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return dotGit.appendingPathComponent("modules")
        }
        // Linked worktree: `.git` is a file containing `gitdir: <path>`.
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              let gitdirLine = contents.split(whereSeparator: \.isNewline).first(where: {
                  $0.trimmingCharacters(in: .whitespaces).hasPrefix("gitdir:")
              }) else {
            return nil
        }
        var gitdir = String(gitdirLine)
            .replacingOccurrences(of: "gitdir:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !NSString(string: gitdir).isAbsolutePath {
            gitdir = repositoryURL.appendingPathComponent(gitdir).standardizedFileURL.path
        }
        let gitDirURL = URL(fileURLWithPath: gitdir).standardizedFileURL
        let components = gitDirURL.pathComponents
        if let worktreesIndex = components.lastIndex(of: "worktrees"), worktreesIndex > 1 {
            let base = "/" + components[1..<worktreesIndex].joined(separator: "/")
            return URL(fileURLWithPath: base).appendingPathComponent("modules")
        }
        return gitDirURL.appendingPathComponent("modules")
    }

    static func relativePath(for url: URL, in repositoryURL: URL) -> String? {
        let root = repositoryURL.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate != root,
              candidate.pathComponents.starts(with: root.pathComponents) else {
            return nil
        }

        return candidate.pathComponents
            .dropFirst(root.pathComponents.count)
            .joined(separator: "/")
    }

}
