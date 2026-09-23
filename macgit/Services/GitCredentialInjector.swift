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

struct GitCredential: Equatable {
    var username: String
    var token: String
}

struct GitSSHCredential: Equatable {
    var username: String
    var keyPath: String
}

struct GitCredentialInjection {
    var environment: [String: String]
    var cleanup: () -> Void
}

protocol GitCredentialInjecting {
    func injection(for credential: GitCredential) throws -> GitCredentialInjection
}

protocol GitSSHCredentialInjecting {
    func injection(for credential: GitSSHCredential) throws -> GitCredentialInjection
}

struct TemporaryGitCredentialInjector: GitCredentialInjecting {
    private let fileManager: FileManager
    private let temporaryDirectory: URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func injection(for credential: GitCredential) throws -> GitCredentialInjection {
        let directory = temporaryDirectory
            .appendingPathComponent("macgit-git-credential-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let usernameURL = directory.appendingPathComponent("username", isDirectory: false)
        let tokenURL = directory.appendingPathComponent("token", isDirectory: false)
        let helperURL = directory.appendingPathComponent("askpass", isDirectory: false)

        try writeProtected(credential.username, to: usernameURL, executable: false)
        try writeProtected(credential.token, to: tokenURL, executable: false)
        try writeProtected(helperScript, to: helperURL, executable: true)

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = helperURL.path
        environment["MACGIT_GIT_USERNAME_FILE"] = usernameURL.path
        environment["MACGIT_GIT_TOKEN_FILE"] = tokenURL.path
        appendGitConfiguration(key: "credential.helper", value: "", to: &environment)

        return GitCredentialInjection(environment: environment) {
            try? fileManager.removeItem(at: directory)
        }
    }

    private func writeProtected(_ value: String, to url: URL, executable: Bool) throws {
        try value.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes(
            [.posixPermissions: executable ? 0o700 : 0o600],
            ofItemAtPath: url.path
        )
    }

    private func appendGitConfiguration(
        key: String,
        value: String,
        to environment: inout [String: String]
    ) {
        let count = Int(environment["GIT_CONFIG_COUNT"] ?? "") ?? 0
        environment["GIT_CONFIG_KEY_\(count)"] = key
        environment["GIT_CONFIG_VALUE_\(count)"] = value
        environment["GIT_CONFIG_COUNT"] = String(count + 1)
    }

    private var helperScript: String {
        """
        #!/bin/sh
        if [ -n "$MACGIT_GIT_CREDENTIAL_HOST" ]; then
          case "$1" in
            *"$MACGIT_GIT_CREDENTIAL_SCHEME://"*)
              authority=${1#*://}
              authority=${authority%%/*}
              authority=${authority%%\\'*}
              authority=${authority##*@}
              [ "$authority" = "$MACGIT_GIT_CREDENTIAL_HOST" ] || exit 1
              ;;
            *) exit 1 ;;
          esac
        fi
        case "$1" in
          *sername*|*USERNAME*)
            /usr/bin/printf '%s\n' "$(/bin/cat "$MACGIT_GIT_USERNAME_FILE")"
            ;;
          *)
            /usr/bin/printf '%s\n' "$(/bin/cat "$MACGIT_GIT_TOKEN_FILE")"
            ;;
        esac
        """
    }
}

struct TemporaryGitSSHCredentialInjector: GitSSHCredentialInjecting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func injection(for credential: GitSSHCredential) throws -> GitCredentialInjection {
        guard fileManager.fileExists(atPath: credential.keyPath) else {
            throw GitProviderCredentialError.sshKeyMissing(path: credential.keyPath)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "/usr/bin/ssh -i \(shellQuoted(credential.keyPath)) -o IdentitiesOnly=yes"

        return GitCredentialInjection(environment: environment, cleanup: {})
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
