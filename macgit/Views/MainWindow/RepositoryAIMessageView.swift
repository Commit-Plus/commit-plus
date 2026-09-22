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

import AppKit
import MarkdownUI
import SwiftUI

struct RepositoryAIMessageView: View {
    let message: RepositoryAIMessage

    var body: some View {
        RepositoryAIMessageRowLayout(
            alignsTrailing: message.role == .user,
            maximumWidthFraction: 0.82
        ) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: roleImage)
                    Text(roleTitle)
                    if let contextTitle = message.contextTitle {
                        Text("· \(contextTitle)")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                if let toolResult = message.toolResult {
                    toolActivity(toolResult)
                } else if message.role == .assistant {
                    Markdown(message.text)
                        .markdownCodeSyntaxHighlighter(RepositoryAICodeSyntaxHighlighter())
                        .markdownTextStyle {
                            FontSize(.em(0.94))
                        }
                        .textSelection(.enabled)
                    citations
                } else {
                    Text(message.text)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(message.role == .user
                        ? Color.accentColor.opacity(0.11)
                        : Color.primary.opacity(0.065))
                    .stroke(.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var citations: some View {
        if !message.citations.isEmpty {
            HStack(spacing: 6) {
                ForEach(message.citations) { citation in
                    Menu {
                        Button("Copy citation text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(citation.label, forType: .string)
                        }
                        if let path = message.evidenceManifest?.evidence(for: citation)?.reference.path {
                            Button("Copy path") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }
                        }
                    } label: {
                        Label(citation.label, systemImage: "quote.opening")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .pointingHandCursor()
                    .accessibilityLabel("Citation: \(citation.label)")
                    .help("Citation actions")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private var roleImage: String {
        switch message.role {
        case .user: "person.crop.circle"
        case .assistant: "sparkles"
        case .toolActivity: "terminal"
        }
    }

    private var roleTitle: String {
        switch message.role {
        case .user: "You"
        case .assistant: "Commit+"
        case .toolActivity: "Repository activity"
        }
    }

    private func toolActivity(_ toolResult: RepositoryAIAgentToolResult) -> some View {
        DisclosureGroup {
            Text(toolResult.commandResult.displayCommand)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text(toolResult.commandResult.output)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            Text(activityTitle(for: toolResult))
                .pointingHandCursor()
        }
        .font(.callout)
        .accessibilityLabel("Repository activity: \(activityTitle(for: toolResult))")
        .accessibilityValue(toolResult.commandResult.succeeded ? "Succeeded" : "Failed")
    }

    private func activityTitle(for toolResult: RepositoryAIAgentToolResult) -> String {
        let arguments = toolResult.toolCall.arguments
        if arguments.starts(with: ["diff", "--cached"]) || arguments.contains("--staged") {
            return "Read staged diff"
        } else if arguments.first == "diff" {
            return "Read working-tree diff"
        } else if arguments.first == "status" {
            return "Inspected repository status"
        } else if arguments.first == "log" || arguments.first == "show" {
            return "Inspected history"
        } else {
            return "Ran read-only Git query"
        }
    }
}
