// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import SwiftUI
import SharedKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ShareX")
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Capture stubs fill in as Phase 1 lands
        let captureRegion = NSMenuItem(title: "Capture Region (Phase 1)", action: nil, keyEquivalent: "")
        captureRegion.isEnabled = false
        menu.addItem(captureRegion)
        let captureScreen = NSMenuItem(title: "Capture Full Screen (Phase 1)", action: nil, keyEquivalent: "")
        captureScreen.isEnabled = false
        menu.addItem(captureScreen)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Main Window…", action: #selector(showMainWindow), keyEquivalent: ""))
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ShareX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { $0.target = $0.action != nil ? self : nil }
        return menu
    }

    @objc private func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeWindow(title: "ShareX", size: NSSize(width: 640, height: 420), view: AnyView(MainWindowView()))
        }
        present(mainWindow)
    }

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "ShareX Settings", size: NSSize(width: 520, height: 400), view: AnyView(SettingsView()))
        }
        present(settingsWindow)
    }

    private func makeWindow(title: String, size: NSSize, view: AnyView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, with replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        // ponytail: log only; sharex:// actions dispatch into the task pipeline from Phase 2 on
        NSLog("ShareX received URL: %@", urlString)
    }
}
