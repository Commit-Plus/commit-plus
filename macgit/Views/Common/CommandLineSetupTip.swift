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
import SwiftUI

struct CommandLineSetupTip: View {
    var installOnPresentation = false
    @Environment(\.dismiss) private var dismiss
    @State private var model = CommandLineSetupModel()
    @State private var copiedCommand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Open repositories from Terminal", systemImage: "terminal")
                .font(.title2.bold())
            Text("Type commit or commit . inside a repository to open it in Commit+.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if installOnPresentation && model.isInstalled {
                    Label("Command line tool is installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text((model.installedCommand ?? model.destination).path)
                        .font(.callout)
                        .textSelection(.enabled)
                } else if model.isReady {
                    Label("CLI and PATH are installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Open a new terminal tab or window to use commit.")
                } else {
                    Button("Install CLI & Configure PATH", action: model.install)
                        .buttonStyle(.borderedProminent)
                    Text("Creates ~/.local/bin/commit and adds PATH to your shell configuration. Existing configuration is kept and backed up.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Step by step").font(.headline)
                if model.isReady {
                    Text("PATH is configured. Open a new terminal tab or window, go to your repository folder, and run:")
                } else if installOnPresentation && model.isInstalled {
                    Text("The CLI is installed. Configure PATH in Settings → General → Command Line, then open a new terminal tab or window and run this from your repository folder:")
                } else {
                    Text("1. Click Install CLI & Configure PATH above. PATH is configured automatically and existing shell configuration is backed up.")
                    Text("2. Open a new terminal tab or window, go to your repository folder, and run:")
                }
                CommandLineCodeBlock(command: "commit .", copiedCommand: $copiedCommand)
                Text("Optional: to use commit in your current terminal tab without opening a new one, run:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                CommandLineCodeBlock(
                    command: model.shellConfiguration.command,
                    copiedCommand: $copiedCommand
                )
                Text("You can also install it later in Settings → General → Command Line.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !installOnPresentation {
                    Button("Don't remind", action: dontRemind)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            model.refresh()
            if installOnPresentation && !model.isInstalled {
                model.install()
            }
        }
    }

    private func dontRemind() {
        CommandLineReminderPolicy.shared.dontRemind()
        dismiss()
    }
}

struct CommandLineCodeBlock: View {
    let command: String
    @Binding var copiedCommand: String?

    var body: some View {
        HStack(spacing: 10) {
            syntaxColoredCommand
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            Button {
                copyCommand()
            } label: {
                Image(systemName: copiedCommand == command ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copiedCommand == command ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help("Copy command")
            .accessibilityLabel(copiedCommand == command ? "Copied" : "Copy command")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.white.opacity(0.08))
        }
    }

    private var syntaxColoredCommand: Text {
        let prompt = Text("❯ ").foregroundStyle(.secondary)
        if command.hasPrefix("export PATH=") {
            return prompt
                + Text("export").foregroundStyle(.purple)
                + Text(" PATH=").foregroundStyle(.primary)
                + Text("\"$HOME/.local/bin:$PATH\"").foregroundStyle(.orange)
        }
        return prompt + Text("commit").foregroundStyle(.blue) + Text(" .").foregroundStyle(.primary)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommand = command
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if copiedCommand == command {
                copiedCommand = nil
            }
        }
    }
}
