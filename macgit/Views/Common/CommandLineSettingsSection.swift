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

import SwiftUI

struct CommandLineSettingsSection: View {
    @State private var model = CommandLineSetupModel()
    @State private var copiedCommand: String?

    var body: some View {
        Section {
            Text("Open a repository from Terminal with commit or commit .")
            LabeledContent(
                model.isInstalled ? "Installed CLI" : "Install location",
                value: (model.installedCommand ?? model.destination).path
            )
            if model.isReady {
                Label("CLI and PATH installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                SettingsActionRow {
                    Button(model.isInstalled ? "Configure PATH" : "Install CLI & Configure PATH", action: model.install)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(model.isReady
                ? "PATH is configured. Open a new terminal tab or window to use commit."
                : "Installation configures PATH automatically and backs up existing shell configuration. Open a new terminal tab or window afterward.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("After installation, open a repository folder in Terminal and run")
                Text("commit .")
                    .font(.system(.callout, design: .monospaced).bold())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                Text("to open it in Commit+.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Text("Optional: to use commit in your current terminal tab without opening a new one, run:")
                .font(.callout)
                .foregroundStyle(.secondary)
            CommandLineCodeBlock(
                command: model.shellConfiguration.command,
                copiedCommand: $copiedCommand
            )
            Text("Run command -v commit in Terminal to check which command your shell uses. Existing aliases and functions may take precedence.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let message = model.errorMessage {
                Text(message).foregroundStyle(.red).textSelection(.enabled)
            }
        } header: {
            Label("Command Line", systemImage: "terminal")
        }
        .onAppear(perform: model.refresh)
    }
}
