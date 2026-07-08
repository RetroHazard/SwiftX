// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import SharedKit

SingleInstance.acquireOrExit()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar app, no Dock icon
app.run()

enum SingleInstance {
    private static var lockFileDescriptor: Int32 = -1

    static func acquireOrExit() {
        try? FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
        let path = SettingsPaths.root.appendingPathComponent(".sharex.lock").path
        lockFileDescriptor = open(path, O_CREAT | O_RDWR, 0o644)
        if lockFileDescriptor == -1 || flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            // ponytail: just exit; forwarding args to the running instance lands with the CLI (Phase 10)
            print("ShareX is already running.")
            exit(0)
        }
        // fd stays open for process lifetime to hold the lock
    }
}
