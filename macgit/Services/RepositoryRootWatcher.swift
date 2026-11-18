// SPDX-License-Identifier: AGPL-3.0-or-later
import CoreServices
import Foundation

/// Watches Your Repos scan roots and reports when a repository may have appeared, moved, or disappeared.
final class RepositoryRootWatcher {
    private final class Handler {
        let onChange: @Sendable () -> Void
        init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }

    private let queue = DispatchQueue(label: "dev.thanhtran.macgit.repository-root-watcher", qos: .utility)
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var handler: Unmanaged<Handler>?
    private var paths: [String] = []

    init(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    deinit { stop() }

    func watch(_ roots: [URL]) {
        let paths = roots.map(\.path)
        guard paths != self.paths else { return }
        stop()
        self.paths = paths
        guard !paths.isEmpty else { return }
        let handler = Unmanaged.passRetained(Handler(onChange: onChange))
        var context = FSEventStreamContext(version: 0, info: handler.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, Self.callback, &context, paths as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else {
            handler.release()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        self.handler = handler
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        paths = []
        // Release after any callback already queued on the serial queue has finished.
        if let handler { queue.async { handler.release() } }
        handler = nil
    }

    private static let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
        guard let info else { return }
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        for index in 0..<count {
            guard let path = paths[index] as? String,
                  isRelevant(path: path, flags: Int(eventFlags[index])) else { continue }
            Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().onChange()
            return
        }
    }

    /// Repository membership changes only when a `.git` entry appears or disappears, a folder is moved or
    /// deleted, or FSEvents asks for a full rescan. Activity inside `.git` and ordinary file edits are ignored.
    static func isRelevant(path: String, flags: Int) -> Bool {
        let rescan = kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagRootChanged
            | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
        if flags & rescan != 0 { return true }
        if path.contains("/.git/") { return false }
        let structural = kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        if (path as NSString).lastPathComponent == ".git" { return flags & structural != 0 }
        let moved = kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemRenamed
        return flags & kFSEventStreamEventFlagItemIsDir != 0 && flags & moved != 0
    }
}
