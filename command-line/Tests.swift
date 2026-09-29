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

@main
struct CommandLineTests {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        func rejects(_ body: () throws -> Void) {
            do { try body(); preconditionFailure("Expected rejection") } catch { checks += 1 }
        }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("commit-cli-tests-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temporary) }
        let unusual = temporary.appendingPathComponent("repo tiếng Việt #&?% + \n")
        try manager.createDirectory(at: unusual, withIntermediateDirectories: true)
        let url = RepositoryOpenRequest.url(for: unusual)
        check(try RepositoryOpenRequest.repositoryURL(from: url).path == unusual.path, "URL round trip")
        check(try RepositoryOpenRequest.directory(arguments: [], currentDirectory: unusual.path).path == unusual.path, "No args")
        check(try RepositoryOpenRequest.directory(arguments: ["."], currentDirectory: unusual.path).path == unusual.path, "Dot")
        check(try RepositoryOpenRequest.directory(arguments: ["--", "-repo"], currentDirectory: temporary.path).lastPathComponent == "-repo", "Literal dash")
        rejects { _ = try RepositoryOpenRequest.directory(arguments: ["a", "b"], currentDirectory: temporary.path) }
        rejects { _ = try RepositoryOpenRequest.directory(arguments: ["--unknown"], currentDirectory: temporary.path) }
        for raw in ["macgit://open-repository?path=relative", "macgit://open-repository?path=/a&path=/b", "macgit://open-repository?path=/a&extra=x", "macgit://open-repository?path=%00", "macgit://open-repository/other?path=/a", "macgit://session?path=/a"] {
            rejects { _ = try RepositoryOpenRequest.repositoryURL(from: URL(string: raw)!) }
        }
        func git(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            precondition(process.terminationStatus == 0, "Git fixture failed")
        }
        try git(["init", unusual.path])
        let defaultsName = "commit-cli-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let runtime = GitRuntimeManager(configuration: GitRuntimeConfiguration(
            applicationSupportDirectory: temporary,
            candidateSystemGitURLs: [URL(fileURLWithPath: "/usr/bin/git")],
            manifest: .current, preferenceDefaults: defaults, preferenceKey: "runtime"
        ))
        let resolver = RepositoryPathResolver()
        let root = try await resolver.root(at: unusual, runtime: runtime)
        check(root.path == unusual.resolvingSymlinksInPath().path, "Unborn repo with literal newline")
        let child = unusual.appendingPathComponent("a/b")
        try manager.createDirectory(at: child, withIntermediateDirectories: true)
        check(try await resolver.root(at: child, runtime: runtime) == root, "Subdirectory root")
        setenv("GIT_DIR", "/nonexistent/override", 1)
        setenv("GIT_WORK_TREE", "/nonexistent/worktree", 1)
        check(try await resolver.root(at: child, runtime: runtime) == root, "Ignore inherited Git overrides")
        unsetenv("GIT_DIR")
        unsetenv("GIT_WORK_TREE")
        let link = temporary.appendingPathComponent("linked")
        try manager.createSymbolicLink(at: link, withDestinationURL: child)
        check(try await resolver.root(at: link, runtime: runtime) == root, "Symlink root")
        try git(["-C", unusual.path, "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "--allow-empty", "-m", "fixture"])
        let worktree = temporary.appendingPathComponent("worktree")
        try git(["-C", unusual.path, "worktree", "add", "-b", "fixture", worktree.path])
        check(try await resolver.root(at: worktree, runtime: runtime).path == worktree.resolvingSymlinksInPath().path, "Linked worktree")
        let bare = temporary.appendingPathComponent("bare")
        try git(["init", "--bare", bare.path])
        for invalid in [temporary, temporary.appendingPathComponent("missing"), bare] {
            do { _ = try await resolver.root(at: invalid, runtime: runtime); preconditionFailure("Expected invalid repo") }
            catch { checks += 1 }
        }
        let helper = temporary.appendingPathComponent("helper")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let installer = CommandLineInstaller(directory: temporary.appendingPathComponent("bin"), executable: helper)
        // Keep the fixture independent of commands installed on the host.
        setenv("PATH", "/usr/bin:/bin", 1)
        try installer.install()
        check(installer.isInstalled, "Installed symlink")
        check(installer.installedCommand == installer.destination, "Installed command path")
        try installer.install()
        check(installer.isInstalled, "Idempotent installation")
        let previousAppHelper = temporary
            .appendingPathComponent("Previous/Commit+.app/Contents/Helpers/commit")
        try manager.createDirectory(
            at: previousAppHelper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: previousAppHelper)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: previousAppHelper.path)
        try manager.removeItem(at: installer.destination)
        try manager.createSymbolicLink(at: installer.destination, withDestinationURL: previousAppHelper)
        check(installer.isInstalled, "Recognize CLI from a previous Commit+ app location")
        check(installer.conflict == nil, "Previous Commit+ CLI is not a conflict")
        try manager.removeItem(at: installer.destination)
        try Data("existing command".utf8).write(to: installer.destination)
        rejects { try installer.install() }
        check(try String(contentsOf: installer.destination, encoding: .utf8) == "existing command", "Preserve existing file")
        try manager.removeItem(at: installer.destination)
        try manager.createSymbolicLink(atPath: installer.destination.path, withDestinationPath: "/missing/helper")
        rejects { try installer.install() }
        check(try manager.destinationOfSymbolicLink(atPath: installer.destination.path) == "/missing/helper", "Preserve dangling symlink")
        let shellHome = temporary.appendingPathComponent("shell-home")
        try manager.createDirectory(at: shellHome, withIntermediateDirectories: true)
        let zsh = CommandLineShellConfiguration(home: shellHome, shell: "/bin/zsh", zshDirectory: nil)
        let zshFile = shellHome.appendingPathComponent(".zshrc")
        let original = "# export PATH=\"$HOME/.local/bin:$PATH\"\nalias example='echo existing'\n"
        try Data(original.utf8).write(to: zshFile)
        check(!zsh.isConfigured, "Commented PATH is not configured")
        try zsh.configure()
        check(zsh.isConfigured, "Zsh PATH configured")
        let configured = try String(contentsOf: zshFile, encoding: .utf8)
        check(configured.hasPrefix(original), "Preserve shell configuration")
        try zsh.configure()
        check(try String(contentsOf: zshFile, encoding: .utf8) == configured, "PATH installation is idempotent")
        let backups = try manager.contentsOfDirectory(at: shellHome, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.contains("commitplus-backup") }
        check(backups.count == 1, "One backup only")
        check(try String(contentsOf: backups[0], encoding: .utf8) == original, "Backup preserves original")
        let customZsh = CommandLineShellConfiguration(home: shellHome, shell: "/bin/zsh", zshDirectory: shellHome.appendingPathComponent("custom"))
        try customZsh.configure()
        check(customZsh.isConfigured, "Custom ZDOTDIR")
        let profile = shellHome.appendingPathComponent(".profile")
        try Data("# existing profile\n".utf8).write(to: profile)
        let bash = CommandLineShellConfiguration(home: shellHome, shell: "/bin/bash", zshDirectory: nil)
        try bash.configure()
        check(bash.isConfigured && bash.files.contains(profile), "Bash uses existing login profile and bashrc")
        check(!manager.fileExists(atPath: shellHome.appendingPathComponent(".bash_profile").path), "Do not shadow existing profile")
        let fish = CommandLineShellConfiguration(home: shellHome, shell: "/opt/homebrew/bin/fish", zshDirectory: nil)
        try fish.configure()
        check(fish.isConfigured, "Fish PATH configured")
        let unsupported = CommandLineShellConfiguration(home: shellHome, shell: "/bin/csh", zshDirectory: nil)
        rejects { try unsupported.configure() }
        let linkedHome = temporary.appendingPathComponent("linked-shell")
        try manager.createDirectory(at: linkedHome, withIntermediateDirectories: true)
        let linkedConfig = linkedHome.appendingPathComponent(".zshrc")
        let actualConfig = linkedHome.appendingPathComponent("dotfiles-zshrc")
        try Data(original.utf8).write(to: actualConfig)
        try manager.createSymbolicLink(at: linkedConfig, withDestinationURL: actualConfig)
        try CommandLineShellConfiguration(home: linkedHome, shell: "/bin/zsh", zshDirectory: nil).configure()
        check(try manager.destinationOfSymbolicLink(atPath: linkedConfig.path) == actualConfig.path, "Keep shell config symlink")
        check(try String(contentsOf: actualConfig, encoding: .utf8).hasPrefix(original), "Keep linked config contents")

        let reminderDefaultsName = "commit-reminder-tests-\(UUID().uuidString)"
        let reminderDefaults = UserDefaults(suiteName: reminderDefaultsName)!
        defer { reminderDefaults.removePersistentDomain(forName: reminderDefaultsName) }
        let firstLaunch = CommandLineReminderPolicy(defaults: reminderDefaults)
        check(firstLaunch.claimPresentation(isReady: false), "Show for uninstalled CLI")
        check(!firstLaunch.claimPresentation(isReady: false), "Close does not repeat within launch")
        let nextLaunch = CommandLineReminderPolicy(defaults: reminderDefaults)
        check(nextLaunch.claimPresentation(isReady: false), "Close reminds on next launch")
        check(!CommandLineReminderPolicy(defaults: reminderDefaults).claimPresentation(isReady: true), "Skip installed CLI and PATH")
        nextLaunch.dontRemind()
        check(!CommandLineReminderPolicy(defaults: reminderDefaults).claimPresentation(isReady: false), "Don't remind persists across launches")
        let setup = CommandLineSetupModel(
            installer: CommandLineInstaller(directory: shellHome.appendingPathComponent(".local/bin"), executable: helper),
            shellConfiguration: zsh
        )
        setup.install()
        check(setup.isReady && setup.errorMessage == nil, "One button completes CLI and PATH installation")
        print("Passed \(checks) CLI, resolver, URL, and installation checks.")
    }
}
