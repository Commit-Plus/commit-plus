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

import CoreGraphics
import Foundation

struct RepositoryWindowRequest: Codable, Hashable {
    struct InitialWindowFrame: Codable, Hashable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ frame: CGRect) {
            x = Double(frame.origin.x)
            y = Double(frame.origin.y)
            width = Double(frame.width)
            height = Double(frame.height)
        }

        var rect: CGRect {
            CGRect(
                x: CGFloat(x),
                y: CGFloat(y),
                width: CGFloat(width),
                height: CGFloat(height)
            )
        }
    }

    enum InitialPresentation: String, Codable {
        case repositoryPicker
        case cloneRepository
    }

    let id: UUID
    let repositoryURL: URL?
    let initialPresentation: InitialPresentation
    let shouldFitVisibleScreen: Bool
    let initialWindowFrame: InitialWindowFrame?
    var showsHistory: Bool? = nil

    static func repositoryPicker(id: UUID = UUID()) -> Self {
        Self(
            id: id,
            repositoryURL: nil,
            initialPresentation: .repositoryPicker,
            shouldFitVisibleScreen: false,
            initialWindowFrame: nil
        )
    }

    static func cloneRepository(id: UUID = UUID()) -> Self {
        Self(
            id: id,
            repositoryURL: nil,
            initialPresentation: .cloneRepository,
            shouldFitVisibleScreen: false,
            initialWindowFrame: nil
        )
    }

    static func repository(
        _ repositoryURL: URL,
        shouldFitVisibleScreen: Bool,
        initialWindowFrame: InitialWindowFrame? = nil,
        showsHistory: Bool? = nil,
        id: UUID = UUID()
    ) -> Self {
        Self(
            id: id,
            repositoryURL: repositoryURL,
            initialPresentation: .repositoryPicker,
            shouldFitVisibleScreen: shouldFitVisibleScreen,
            initialWindowFrame: initialWindowFrame,
            showsHistory: showsHistory
        )
    }
}
