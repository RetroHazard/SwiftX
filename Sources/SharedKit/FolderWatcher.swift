// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// FSEvents replaces C#'s FileSystemWatcher: per-file events, recursive by
// default (non-recursive filtered by parent path), delivered on the main queue.

import CoreServices
import Foundation

public final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private let root: String
    private let includeSubdirectories: Bool
    private let filter: String
    private let onFile: (String) -> Void
    /// FSEvents batches can repeat a path; suppress duplicates within 1s (C# duplicate-event timer).
    private var recentlySeen: [String: Date] = [:]

    /// Returns nil when the directory doesn't exist or the stream can't start.
    /// `onFile` fires on the main queue for every new file matching `filter`.
    public init?(path: String, includeSubdirectories: Bool = false, filter: String = "",
                 onFile: @escaping (String) -> Void) {
        let expanded = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        // FSEvents reports canonical paths; resolve symlinks (/var vs /private/var)
        // so the non-recursive parent check compares like with like
        self.root = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().path
        self.includeSubdirectories = includeSubdirectories
        self.filter = filter
        self.onFile = onFile

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // kFSEventStreamCreateFlagUseCFTypes: eventPaths is a CFArray of CFString
            guard let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String]
            else { return }
            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: count))
            watcher.handle(paths: paths, flags: flags)
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [expanded] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
        for (path, flag) in zip(paths, flags) {
            guard flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile) != 0,
                  flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated
                                                 | kFSEventStreamEventFlagItemRenamed) != 0
            else { continue }
            if !includeSubdirectories,
               URL(fileURLWithPath: path).deletingLastPathComponent().resolvingSymlinksInPath().path != root {
                continue
            }
            let name = (path as NSString).lastPathComponent
            if !filter.isEmpty, fnmatch(filter, name, FNM_CASEFOLD) != 0 { continue }
            // renames fire for moves out of the folder too; only report arrivals
            guard FileManager.default.fileExists(atPath: path) else { continue }
            if let seen = recentlySeen[path], Date().timeIntervalSince(seen) < 1 { continue }
            recentlySeen[path] = Date()
            recentlySeen = recentlySeen.filter { Date().timeIntervalSince($0.value) < 5 }
            onFile(path)
        }
    }

    /// C# watch-folder stability gate: poll every 250ms until the size is
    /// unchanged for four checks; give up (but still report existence) after 5s.
    public static func waitUntilStable(path: String) async -> Bool {
        var previousSize = -1
        var stableCount = 0
        for _ in 0..<20 {
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? -1
            if size > 0 && size == previousSize {
                stableCount += 1
                if stableCount >= 4 { return true }
            } else {
                stableCount = 0
            }
            previousSize = size
            try? await Task.sleep(for: .milliseconds(250))
        }
        // ponytail: no POSIX equivalent of the C# file-lock check; upload anyway
        return FileManager.default.fileExists(atPath: path)
    }
}
