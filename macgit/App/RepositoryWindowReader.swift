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

struct RepositoryWindowReader: NSViewRepresentable {
    let repositoryWindowContext: RepositoryWindowContext
    let title: String
    var repositoryURL: URL? = nil
    var allowsTabbing = true

    func makeNSView(context: Context) -> WindowReaderView {
        repositoryWindowContext.repositoryURL = repositoryURL
        return WindowReaderView(
            repositoryWindowContext: repositoryWindowContext,
            title: title,
            allowsTabbing: allowsTabbing
        )
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        repositoryWindowContext.repositoryURL = repositoryURL
        nsView.repositoryWindowContext = repositoryWindowContext
        nsView.title = title
        nsView.allowsTabbing = allowsTabbing
        nsView.configureWindow()
    }

    static func dismantleNSView(_ nsView: WindowReaderView, coordinator: Void) {
        if nsView.repositoryWindowContext.window === nsView.window {
            nsView.repositoryWindowContext.window = nil
        }
    }

    final class WindowReaderView: NSView {
        var repositoryWindowContext: RepositoryWindowContext
        var title: String
        var allowsTabbing: Bool

        init(repositoryWindowContext: RepositoryWindowContext, title: String, allowsTabbing: Bool) {
            self.repositoryWindowContext = repositoryWindowContext
            self.title = title
            self.allowsTabbing = allowsTabbing
            super.init(frame: .zero)
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            guard let window else { return }
            repositoryWindowContext.window = window
            let tabbingIdentifier = allowsTabbing
                ? "com.commitplus.macgit.repository"
                : "com.commitplus.macgit.welcome"
            let tabbingMode: NSWindow.TabbingMode = allowsTabbing ? .automatic : .disallowed
            // AppKit setters can update standard window menu items even when
            // their values are unchanged. Avoid reconfiguring tabs during
            // unrelated SwiftUI updates while a menu is being tracked.
            if window.tabbingIdentifier != tabbingIdentifier {
                window.tabbingIdentifier = tabbingIdentifier
            }
            if window.tabbingMode != tabbingMode {
                window.tabbingMode = tabbingMode
            }
            if window.title != title {
                window.title = title
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
        }
    }
}
