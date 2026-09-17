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

/// A transport boundary for model-supplied Git queries.
///
/// This deliberately does not maintain a grammar for every benign option of
/// every Git subcommand. Git evolves too quickly for that to be reliable, and
/// it prevented ordinary requests such as reviewing an index diff. The policy
/// instead admits only known read-only built-ins, keeps the execution context
/// app-owned, and rejects options that can escape that context or invoke an
/// external helper. Mutations remain a separate, confirmed tool domain.
nonisolated enum RepositoryAIGitCommandPolicy {
    private static let safeGlobalArguments = [
        "--no-pager",
        "-c", "color.ui=false",
        "-c", "core.pager=cat",
    ]

    private static let readOnlyBuiltins: Set<String> = [
        "annotate", "blame", "cat-file", "count-objects", "describe", "diff",
        "diff-files", "diff-index", "diff-tree", "for-each-ref", "fsck", "grep",
        "log", "ls-files", "ls-tree", "merge-base", "name-rev", "rev-list",
        "rev-parse", "show", "show-branch", "status", "symbolic-ref",
        "verify-pack", "whatchanged",
    ]

    /// Commands that can render a diff, and therefore must not invoke an
    /// external diff driver or textconv filter.
    private static let diffProducingBuiltins: Set<String> = [
        "diff", "diff-files", "diff-index", "diff-tree", "log", "show", "whatchanged",
    ]

    static func validatedArguments(_ arguments: [String]) throws -> [String] {
        guard let command = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            throw RepositoryAIGitCommandError.emptyCommand
        }
        guard readOnlyBuiltins.contains(command) else {
            throw RepositoryAIGitCommandError.unsupportedCommand(command)
        }

        let commandArguments = Array(arguments.dropFirst())
        guard commandArguments.allSatisfy(isSafeModelArgument) else {
            throw RepositoryAIGitCommandError.unsupportedArguments(
                "Repository AI cannot use Git options that override its safe execution context."
            )
        }

        let builtinSafetyArguments = diffProducingBuiltins.contains(command)
            ? ["--no-ext-diff", "--no-textconv"]
            : []
        return safeGlobalArguments + [command] + builtinSafetyArguments + commandArguments
    }

    private static func isSafeModelArgument(_ argument: String) -> Bool {
        guard !argument.isEmpty,
              !argument.contains("\0"),
              !argument.contains("\n"),
              !argument.contains("\r") else {
            return false
        }

        let forbiddenExact = [
            "-c", "--config-env", "--git-dir", "--work-tree", "--namespace",
            "--exec-path", "--paginate", "--ext-diff", "--textconv", "--filters", "--no-index",
            "--output",
        ]
        if forbiddenExact.contains(argument) {
            return false
        }

        let forbiddenPrefixes = [
            "-c", "--config-env=", "--git-dir=", "--work-tree=", "--namespace=",
            "--exec-path=", "--output=", "--ext-diff=", "--textconv=", "--filters=",
        ]
        return !forbiddenPrefixes.contains(where: argument.hasPrefix)
    }
}
