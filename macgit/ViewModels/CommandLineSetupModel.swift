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
import Observation

@MainActor
@Observable
final class CommandLineSetupModel {
    private let installer: CommandLineInstaller
    let shellConfiguration: CommandLineShellConfiguration
    private(set) var isInstalled = false
    private(set) var isReady = false
    private(set) var errorMessage: String?

    init(installer: CommandLineInstaller = CommandLineInstaller(),
         shellConfiguration: CommandLineShellConfiguration = CommandLineShellConfiguration()) {
        self.installer = installer
        self.shellConfiguration = shellConfiguration
        refresh()
    }

    var destination: URL { installer.destination }
    var installedCommand: URL? { installer.installedCommand }

    func refresh() {
        isInstalled = installer.isInstalled
        isReady = isInstalled && shellConfiguration.isConfigured
        errorMessage = installer.conflict
    }

    func install() {
        do {
            try installer.install()
            try shellConfiguration.configure()
            refresh()
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }
}
