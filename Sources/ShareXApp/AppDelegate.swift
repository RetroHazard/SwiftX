// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import SwiftUI
import SharedKit
import UploadKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var recordItem: NSMenuItem?
    private var recordGIFItem: NSMenuItem?
    private var abortRecordingItem: NSMenuItem?

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

        setupHotkeys()
        Notifier.setup()
        RecordingCoordinator.shared.onStateChange = { [weak self] in self?.updateRecordingUI() }

        if CommandLine.arguments.contains("--notify-test") {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                NSLog("Notification settings: authorizationStatus=%ld alertSetting=%ld",
                      settings.authorizationStatus.rawValue, settings.alertSetting.rawValue)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Notifier.notify(title: "ShareX test", body: "Notifications are working.")
            }
        }
    }

    private func setupHotkeys() {
        var settings = HotkeySettings.load()
        if settings.hotkeys.isEmpty {
            settings.hotkeys = [
                HotkeyConfig(.printScreen, key: "3", modifiers: ["control", "shift"]),
                HotkeyConfig(.rectangleRegion, key: "4", modifiers: ["control", "shift"]),
                HotkeyConfig(.activeWindow, key: "5", modifiers: ["control", "shift"])
            ]
            try? settings.save()
        }
        for config in settings.hotkeys {
            guard let combo = config.combo, let type = config.type, type != .none else { continue }
            let registered = HotkeyCenter.shared.register(combo, alwaysEnabled: type == .disableHotkeys) {
                HotkeyDispatcher.execute(type)
            }
            if !registered {
                NSLog("Could not register hotkey %@ for %@ (conflict or unknown key)",
                      combo.displayString, config.taskType)
            }
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Active Window", action: #selector(captureActiveWindow), keyEquivalent: ""))

        menu.addItem(.separator())
        let record = NSMenuItem(title: "Record Screen (Region)…", action: #selector(toggleRecording), keyEquivalent: "")
        let recordGIF = NSMenuItem(title: "Record GIF (Region)…", action: #selector(toggleGIFRecording), keyEquivalent: "")
        let abort = NSMenuItem(title: "Abort Recording", action: #selector(abortRecording), keyEquivalent: "")
        abort.isHidden = true
        recordItem = record
        recordGIFItem = recordGIF
        abortRecordingItem = abort
        menu.addItem(record)
        menu.addItem(recordGIF)
        menu.addItem(abort)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Import Custom Uploader…", action: #selector(importCustomUploader), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Main Window…", action: #selector(showMainWindow), keyEquivalent: ""))
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ShareX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { $0.target = $0.action != nil ? self : nil }
        return menu
    }

    @objc private func captureRegion() {
        CaptureCoordinator.shared.captureRegion()
    }

    @objc private func captureFullScreen() {
        CaptureCoordinator.shared.captureFullScreen()
    }

    @objc private func captureActiveWindow() {
        CaptureCoordinator.shared.captureActiveWindow()
    }

    @objc private func toggleRecording() {
        RecordingCoordinator.shared.toggleRegion(gif: false)
    }

    @objc private func toggleGIFRecording() {
        RecordingCoordinator.shared.toggleRegion(gif: true)
    }

    @objc private func abortRecording() {
        RecordingCoordinator.shared.abort()
    }

    private func updateRecordingUI() {
        let recording = RecordingCoordinator.shared.isRecording
        recordItem?.title = recording ? "Stop Recording" : "Record Screen (Region)…"
        recordGIFItem?.isHidden = recording
        abortRecordingItem?.isHidden = !recording
        statusItem?.button?.image = NSImage(
            systemSymbolName: recording ? "record.circle" : "camera.viewfinder",
            accessibilityDescription: "ShareX"
        )
        statusItem?.button?.contentTintColor = recording ? .systemRed : nil
    }

    @objc private func importCustomUploader() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .init(filenameExtension: "sxcu") ?? .json]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let name = try CustomUploaderStore.importFile(from: url)
            var config = UploadersConfig.load()
            if config.activeCustomUploader.isEmpty {
                config.activeCustomUploader = name
                try config.save()
            }
            Notifier.notify(title: "Custom uploader imported", body: name)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Import failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeWindow(title: "ShareX", size: NSSize(width: 640, height: 420), view: AnyView(MainWindowView()))
        }
        present(mainWindow)
    }

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "ShareX Settings", size: NSSize(width: 700, height: 460), view: AnyView(SettingsView()))
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
