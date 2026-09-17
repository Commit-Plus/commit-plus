//
//  FirebaseBootstrap.swift
//  macgit
//

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

import FirebaseCore
import Foundation

enum FirebaseBootstrap {
    /// Unit tests launch the real app as their host. Anything that opens the
    /// shared Firestore LevelDB cache makes concurrent/parallel test hosts abort
    /// at launch with "Failed to open DB". Production stays unchanged; tests only
    /// skip the cloud-backed stores. `FirebaseApp` is still configured so
    /// Auth-backed members stay constructible.
    static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static func configure(bundle: Bundle = .main) -> FirebaseBootstrapStatus {
        if FirebaseApp.app() != nil {
            return .configured
        }

        guard let path = bundle.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            return .missingConfiguration
        }

        FirebaseApp.configure(options: options)
        return .configured
    }
}
