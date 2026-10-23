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

struct GitProviderSSHAuthRequest: Equatable {
    var host: GitProviderHost
    var keyPath: String
}

struct GitProviderSSHAuthentication: Equatable {
    var username: String
}

protocol GitProviderSSHAuthenticating {
    func authenticate(host: GitProviderHost, keyPath: String) async throws -> GitProviderSSHAuthentication
}

struct GitProviderSSHAuthService: GitProviderSSHAuthenticating {
    func authenticate(host: GitProviderHost, keyPath: String) async throws -> GitProviderSSHAuthentication {
        guard FileManager.default.fileExists(atPath: keyPath) else {
            throw GitProviderCredentialError.sshKeyMissing(path: keyPath)
        }
        guard let hostName = host.kind == .azureDevOps
            ? "ssh.dev.azure.com"
            : host.normalized.baseURL.host(percentEncoded: false) else {
            throw GitProviderCredentialError.unsupportedRemote
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        task.arguments = [
            "-T",
            "-i", keyPath,
            "-o", "IdentitiesOnly=yes",
            "-o", "ConnectTimeout=10",
            "git@\(hostName)"
        ]
        task.environment = ProcessInfo.processInfo.environment.merging(["GIT_TERMINAL_PROMPT": "0"]) { _, new in new }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        task.waitUntilExit()

        let output = Self.read(outputPipe) + Self.read(errorPipe)
        if let username = Self.username(from: output, provider: host.kind) {
            return GitProviderSSHAuthentication(username: username)
        }

        throw GitError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func username(from output: String, provider: GitProviderKind) -> String? {
        switch provider {
        case .github:
            return capture(in: output, pattern: #"Hi ([^!]+)!"#)
        case .gitlab:
            return capture(in: output, pattern: #"Welcome to GitLab, @([^!\s]+)"#)
        case .bitbucket:
            return output.localizedCaseInsensitiveContains("authenticated via ssh key") ? "git" : nil
        case .azureDevOps:
            // Azure DevOps accepts the key but never names the user; callers supply the organization.
            return output.localizedCaseInsensitiveContains("shell access is not supported") ? "git" : nil
        }
    }

    private static func capture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range])
    }

    private static func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
