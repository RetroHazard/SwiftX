// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import CaptureKit
import SharedKit

// Headless capture check for development: swiftx --capture-selftest
if CommandLine.arguments.contains("--capture-selftest") {
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let image = try await ScreenCapture.captureDisplay()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftx-selftest.png")
            try ImageWriter.writePNG(image, to: url)
            print("selftest ok: \(image.width)x\(image.height) -> \(url.path)")
        } catch {
            print("selftest failed: \(error.localizedDescription)")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

SingleInstance.acquireOrExit()

// main.swift top-level runs on the main thread; script mode just isn't annotated
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar app, no Dock icon
    withExtendedLifetime(delegate) { // NSApplication.delegate is unowned(unsafe)
        app.run()
    }
}

enum SingleInstance {
    private static var lockFileDescriptor: Int32 = -1

    static func acquireOrExit() {
        try? FileManager.default.createDirectory(at: SettingsPaths.root, withIntermediateDirectories: true)
        let path = SettingsPaths.root.appendingPathComponent(".swiftx.lock").path
        lockFileDescriptor = open(path, O_CREAT | O_RDWR, 0o644)
        if lockFileDescriptor == -1 || flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            let args = CLI.relevantArguments()
            if args.isEmpty {
                print("SwiftX is already running.")
            } else {
                CLIRelay.forward(args)
                print("SwiftX is already running; arguments forwarded.")
            }
            exit(0)
        }
        // fd stays open for process lifetime to hold the lock
    }
}
