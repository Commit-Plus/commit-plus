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
@MainActor
final class RepositoryWindowContext {
    private static let contexts = NSHashTable<RepositoryWindowContext>.weakObjects()
    private static var pendingRepositories = Set<URL>()
    private static var pendingUndoEntries: [URL: [GitUndoEntry]] = [:]
    weak var gitUndoManager: GitUndoManager?
    weak var syncState: SyncState?
    weak var window: NSWindow?
    var repositoryURL: URL? {
        didSet {
            if let repositoryURL {
                Self.pendingRepositories.remove(repositoryURL.resolvingSymlinksInPath().standardizedFileURL)
            }
        }
    }

    static func reserveOpening(_ url: URL) -> Bool {
        pendingRepositories.insert(url).inserted
    }

    init() {
        Self.contexts.add(self)
    }

    static func focusRepository(at url: URL) -> Bool {
        guard let context = contexts.allObjects.first(where: {
            $0.repositoryURL?.resolvingSymlinksInPath().standardizedFileURL == url
                && ($0.window?.isVisible == true || $0.window?.isMiniaturized == true
                    || $0.window?.tabGroup?.windows.contains(where: { $0.isVisible || $0.isMiniaturized }) == true)
        }), let window = context.window else { return false }
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func attachUndoManager(_ manager: GitUndoManager, syncState: SyncState, for url: URL) {
        gitUndoManager = manager
        self.syncState = syncState
        let key = url.resolvingSymlinksInPath().standardizedFileURL
        for entry in Self.pendingUndoEntries.removeValue(forKey: key) ?? [] {
            manager.register(entry)
        }
    }

    static func registerTransferredUndo(_ entry: GitUndoEntry) {
        let key = entry.repositoryURL.resolvingSymlinksInPath().standardizedFileURL
        if let manager = contexts.allObjects.first(where: {
            $0.repositoryURL?.resolvingSymlinksInPath().standardizedFileURL == key && $0.gitUndoManager != nil
        })?.gitUndoManager {
            manager.register(entry)
        } else {
            pendingUndoEntries[key, default: []].append(entry)
        }
    }

    static func refreshRepository(at url: URL) async {
        let key = url.resolvingSymlinksInPath().standardizedFileURL
        for context in contexts.allObjects where
            context.repositoryURL?.resolvingSymlinksInPath().standardizedFileURL == key {
            await context.syncState?.refresh(repositoryURL: url)
        }
    }

    func owns(_ notification: Notification) -> Bool {
        guard let targetWindow = notification.object as? NSWindow else { return false }
        return targetWindow === window
    }
}
