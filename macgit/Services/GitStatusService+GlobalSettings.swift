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

extension GitStatusService {
    func loadGlobalGitSettings() async throws -> GlobalGitSettings {
        let directory = FileManager.default.homeDirectoryForCurrentUser
        let version = try await runGit(arguments: ["--version"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return GlobalGitSettings(
            executablePath: try await gitExecutable(),
            version: version,
            userName: await globalConfigValue("user.name", in: directory) ?? "",
            userEmail: await globalConfigValue("user.email", in: directory) ?? "",
            defaultBranchName: await globalConfigValue("init.defaultBranch", in: directory) ?? "main",
            pruneOnFetch: await globalConfigBool("fetch.prune", in: directory),
            autoSetupRemote: await globalConfigBool("push.autoSetupRemote", in: directory),
            excludesFilePath: await globalConfigValue("core.excludesFile", in: directory)
                ?? "~/.config/git/ignore",
            credentialHelperValues: await globalConfigValues("credential.helper", in: directory)
        )
    }

    func updateGlobalGitSettings(
        _ settings: GlobalGitSettings,
        credentialHelperMode: GitCredentialHelperMode? = nil
    ) async throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser
        let name = settings.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = settings.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = settings.defaultBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let excludesFile = settings.excludesFilePath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            throw GitError.commandFailed("Global Git author name is required.")
        }
        guard email.contains("@"), !email.contains(where: \.isWhitespace) else {
            throw GitError.commandFailed("Enter a valid email address for your global Git author.")
        }
        guard !branch.isEmpty else {
            throw GitError.commandFailed("Default branch name is required.")
        }

        _ = try await runGit(arguments: ["check-ref-format", "--branch", branch], in: directory)
        if let credentialHelperMode {
            try await updateGlobalCredentialHelper(credentialHelperMode, in: directory)
        }
        try await setGlobalConfig("user.name", value: name, in: directory)
        try await setGlobalConfig("user.email", value: email, in: directory)
        try await setGlobalConfig("init.defaultBranch", value: branch, in: directory)
        try await setGlobalConfig("fetch.prune", value: settings.pruneOnFetch ? "true" : "false", in: directory)
        try await setGlobalConfig(
            "push.autoSetupRemote",
            value: settings.autoSetupRemote ? "true" : "false",
            in: directory
        )

        if excludesFile.isEmpty {
            _ = try? await runGit(
                arguments: ["config", "--global", "--unset-all", "core.excludesFile"],
                in: directory
            )
        } else {
            try await setGlobalConfig("core.excludesFile", value: excludesFile, in: directory)
        }
    }

    func availableCredentialHelpers() async -> [String] {
        let directory = FileManager.default.homeDirectoryForCurrentUser
        guard let output = try? await runGit(arguments: ["help", "-a"], in: directory) else {
            return []
        }

        let helpers = Set(output.split(whereSeparator: \Character.isWhitespace).compactMap { token -> String? in
            let command = String(token)
            let prefix = "credential-"
            guard command.hasPrefix(prefix) else { return nil }
            let name = String(command.dropFirst(prefix.count))
            guard !name.isEmpty, !name.contains("--"), name != "store" else { return nil }
            return name
        })

        return helpers.sorted { lhs, rhs in
            if lhs == "osxkeychain" { return true }
            if rhs == "osxkeychain" { return false }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func globalConfigValue(_ key: String, in directory: URL) async -> String? {
        let value = try? await runGit(
            arguments: ["config", "--global", "--get", key],
            in: directory
        )
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func globalConfigValues(_ key: String, in directory: URL) async -> [String] {
        guard let output = try? await runGit(
            arguments: ["config", "--global", "--get-all", key],
            in: directory
        ), !output.isEmpty else {
            return []
        }

        return configValues(from: output)
    }

    private func requiredGlobalConfigValues(_ key: String, in directory: URL) async throws -> [String] {
        do {
            let output = try await runGit(
                arguments: ["config", "--global", "--get-all", key],
                in: directory
            )
            return configValues(from: output)
        } catch GitError.commandFailed(let message) where message.isEmpty {
            return []
        }
    }

    private func configValues(from output: String) -> [String] {
        guard !output.isEmpty else { return [] }
        var values = output.components(separatedBy: "\n")
        if values.last == "" {
            values.removeLast()
        }
        return values
    }

    private func globalConfigBool(_ key: String, in directory: URL) async -> Bool {
        guard let value = await globalConfigValue(key, in: directory)?.lowercased() else {
            return false
        }
        return ["true", "yes", "on", "1"].contains(value)
    }

    private func setGlobalConfig(_ key: String, value: String, in directory: URL) async throws {
        _ = try await runGit(
            arguments: ["config", "--global", key, value],
            in: directory
        )
    }

    private func updateGlobalCredentialHelper(
        _ mode: GitCredentialHelperMode,
        in directory: URL
    ) async throws {
        switch mode {
        case .preserveExisting:
            return
        case .helper(let helper):
            let availableHelpers = await availableCredentialHelpers()
            guard availableHelpers.contains(helper) else {
                throw GitError.commandFailed(
                    "The credential helper '\(helper)' is not available to the active Git runtime."
                )
            }
        case .commitPlusAccountsOnly:
            break
        }

        let previousValues = try await requiredGlobalConfigValues("credential.helper", in: directory)
        _ = try await runGit(
            arguments: ["config", "--global", "--replace-all", "credential.helper", ""],
            in: directory
        )

        do {
            if case .helper(let helper) = mode {
                _ = try await runGit(
                    arguments: ["config", "--global", "--add", "credential.helper", helper],
                    in: directory
                )
            }

            let savedValues = try await requiredGlobalConfigValues("credential.helper", in: directory)
            guard GitCredentialHelperMode.resolve(configuredValues: savedValues) == mode else {
                throw GitError.commandFailed("Git did not save the selected credential helper configuration.")
            }
        } catch {
            let replacementError = error
            do {
                try await restoreGlobalCredentialHelpers(previousValues, in: directory)
            } catch {
                throw GitError.commandFailed(
                    "\(replacementError.localizedDescription) Restoring the previous credential helpers also failed: \(error.localizedDescription)"
                )
            }
            throw replacementError
        }
    }

    private func restoreGlobalCredentialHelpers(_ values: [String], in directory: URL) async throws {
        guard let first = values.first else {
            _ = try await runGit(
                arguments: ["config", "--global", "--unset-all", "credential.helper"],
                in: directory
            )
            return
        }

        _ = try await runGit(
            arguments: ["config", "--global", "--replace-all", "credential.helper", first],
            in: directory
        )
        for value in values.dropFirst() {
            _ = try await runGit(
                arguments: ["config", "--global", "--add", "credential.helper", value],
                in: directory
            )
        }
    }
}
