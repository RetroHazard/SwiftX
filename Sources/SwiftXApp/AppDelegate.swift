// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import CaptureKit
import EffectsKit
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
    private var pauseRecordingItem: NSMenuItem?
    private var abortRecordingItem: NSMenuItem?
    private let screensSubmenu = NSMenu()
    private let windowsSubmenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "SwiftX")
        item.menu = buildMenu()
        statusItem = item

        // watermark text (%h, %mi, ...) runs through the ShareX pattern parser
        EffectsEnvironment.textParser = { NameParser(.text).parse($0) }

        setupHotkeys()
        Notifier.setup()
        WatchFolderCenter.shared.applySettings()
        CLIRelay.startListening()
        NameParser.onError = { message in
            Task { @MainActor in Notifier.notify(title: "Name parser", body: message) }
        }
        let launchArgs = CLI.relevantArguments()
        if !launchArgs.isEmpty {
            Task { await CLI.handle(launchArgs) }
        }
        RecordingCoordinator.shared.onStateChange = { [weak self] in self?.updateRecordingUI() }

        // debug: upload a file through the full pipeline, then report what the
        // after-upload tasks left on the pasteboard
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--upload-test"),
           CommandLine.arguments.indices.contains(flagIndex + 1) {
            let path = CommandLine.arguments[flagIndex + 1]
            UploadCoordinator.uploadFile(at: URL(fileURLWithPath: path))
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                NSLog("upload-test pasteboard: %@", NSPasteboard.general.string(forType: .string) ?? "<empty>")
            }
        }

        if CommandLine.arguments.contains("--notify-test") {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                NSLog("Notification settings: authorizationStatus=%ld alertSetting=%ld",
                      settings.authorizationStatus.rawValue, settings.alertSetting.rawValue)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Notifier.notify(title: "SwiftX test", body: "Notifications are working.")
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
        HotkeyRegistrar.applyAll()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Capture Active Window", action: #selector(captureActiveWindow), keyEquivalent: ""))

        // pickers populate on open: displays and windows change constantly
        screensSubmenu.delegate = self
        windowsSubmenu.delegate = self
        let screenPicker = NSMenuItem(title: "Capture Screen…", action: nil, keyEquivalent: "")
        screenPicker.submenu = screensSubmenu
        menu.addItem(screenPicker)
        let windowPicker = NSMenuItem(title: "Capture Window…", action: nil, keyEquivalent: "")
        windowPicker.submenu = windowsSubmenu
        menu.addItem(windowPicker)
        menu.addItem(NSMenuItem(title: "Capture Last Region", action: #selector(captureLastRegion), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Scrolling Capture…", action: #selector(showScrollingCapture), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Auto Capture…", action: #selector(showAutoCapture), keyEquivalent: ""))

        menu.addItem(.separator())
        let record = NSMenuItem(title: "Record Screen (Region)…", action: #selector(toggleRecording), keyEquivalent: "")
        let recordGIF = NSMenuItem(title: "Record GIF (Region)…", action: #selector(toggleGIFRecording), keyEquivalent: "")
        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePauseRecording), keyEquivalent: "")
        pause.isHidden = true
        let abort = NSMenuItem(title: "Abort Recording", action: #selector(abortRecording), keyEquivalent: "")
        abort.isHidden = true
        recordItem = record
        recordGIFItem = recordGIF
        pauseRecordingItem = pause
        abortRecordingItem = abort
        menu.addItem(record)
        menu.addItem(recordGIF)
        menu.addItem(pause)
        menu.addItem(abort)

        menu.addItem(.separator())
        let tools = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        tools.submenu = buildToolsMenu()
        menu.addItem(tools)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Main Window…", action: #selector(showMainWindow), keyEquivalent: ""))
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About SwiftX", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit SwiftX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items.forEach { $0.target = $0.action != nil ? self : nil }
        return menu
    }

    /// Mirrors the C# Tools menu; every item routes through HotkeyDispatcher
    /// so the menu and hotkeys always agree on behavior.
    private func buildToolsMenu() -> NSMenu {
        let entries: [(String, HotkeyType)?] = [
            ("Color Picker…", .colorPicker),
            ("Screen Color Picker", .screenColorPicker),
            ("Ruler", .ruler),
            ("Pin Image File to Screen…", .pinToScreenFromFile),
            nil,
            ("Image Viewer…", .imageViewer),
            ("Image Combiner…", .imageCombiner),
            ("Image Splitter…", .imageSplitter),
            ("Image Thumbnailer…", .imageThumbnailer),
            ("Image Effects…", .imageEffects),
            ("Image Beautifier…", .imageBeautifier),
            nil,
            ("Video Converter…", .videoConverter),
            ("Video Thumbnailer…", .videoThumbnailer),
            nil,
            ("AI Image Analysis…", .analyzeImage),
            ("OCR…", .ocr),
            ("QR Code…", .qrCode),
            ("Hash Checker…", .hashCheck),
            ("Image Metadata…", .metadata),
            ("Index Folder…", .indexFolder),
            nil,
            ("Clipboard Viewer…", .clipboardViewer),
            ("Inspect Window…", .inspectWindow),
            ("Monitor Test", .monitorTest)
        ]
        let toolsMenu = NSMenu()
        for entry in entries {
            guard let (title, type) = entry else { toolsMenu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: #selector(toolMenuAction(_:)), keyEquivalent: "")
            item.representedObject = type.rawValue
            item.target = self
            toolsMenu.addItem(item)
        }
        return toolsMenu
    }

    @objc private func toolMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let type = HotkeyType(rawValue: raw) else { return }
        HotkeyDispatcher.execute(type)
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

    @objc private func captureLastRegion() {
        CaptureCoordinator.shared.captureLastRegion()
    }

    @objc private func showAutoCapture() {
        AutoCaptureController.show()
    }

    @objc private func showScrollingCapture() {
        ScrollingCaptureController.show()
    }

    @objc private func captureScreenItem(_ sender: NSMenuItem) {
        guard let screen = sender.representedObject as? NSScreen else { return }
        CaptureCoordinator.shared.captureScreen(screen)
    }

    @objc private func captureWindowItem(_ sender: NSMenuItem) {
        guard let window = sender.representedObject as? CapturableWindow else { return }
        CaptureCoordinator.shared.captureWindow(window)
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

    @objc private func togglePauseRecording() {
        RecordingCoordinator.shared.togglePause()
    }

    private func updateRecordingUI() {
        let recording = RecordingCoordinator.shared.isRecording
        recordItem?.title = recording ? "Stop Recording" : "Record Screen (Region)…"
        recordGIFItem?.isHidden = recording
        pauseRecordingItem?.isHidden = !recording
        pauseRecordingItem?.title = RecordingCoordinator.shared.isPaused ? "Resume Recording" : "Pause Recording"
        abortRecordingItem?.isHidden = !recording
        statusItem?.button?.image = NSImage(
            systemSymbolName: recording ? "record.circle" : "camera.viewfinder",
            accessibilityDescription: "SwiftX"
        )
        statusItem?.button?.contentTintColor = recording ? .systemRed : nil
    }

    /// ToggleTrayMenu hotkey: pops the status-item menu open.
    func toggleStatusMenu() {
        statusItem?.button?.performClick(nil)
    }

    @objc func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeWindow(title: "SwiftX", size: NSSize(width: 640, height: 420), view: AnyView(MainWindowView()))
        }
        present(mainWindow)
    }

    /// Standard About panel; the credits string carries the GPL v3
    /// "Appropriate Legal Notices": both copyright notices, the no-warranty
    /// statement, and a link to the bundled license text.
    @objc private func showAbout() {
        let small = NSFont.smallSystemFontSize
        let footnote = NSFont.systemFontSize(for: .mini)
        let credits = NSMutableAttributedString()
        func append(_ text: String, size: CGFloat, color: NSColor = .labelColor, link: String? = nil) {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size), .foregroundColor: color
            ]
            if let link { attributes[.link] = link }
            credits.append(NSAttributedString(string: text, attributes: attributes))
        }

        append("Project page", size: small, link: "https://github.com/RetroHazard/SwiftX")
        append("  ·  ", size: small, color: .tertiaryLabelColor)
        append("Report an issue", size: small, link: "https://github.com/RetroHazard/SwiftX/issues")

        append("\nmacOS port © 2026 ", size: small)
        append("RetroHazard", size: small, link: "https://github.com/RetroHazard")
        // U+2028 breaks the line without ending the paragraph, so the
        // paragraphSpacing gap only lands between the three blocks
        append("\u{2028}Based on ", size: small, color: .secondaryLabelColor)
        append("ShareX", size: small, link: "https://github.com/ShareX/ShareX")
        append(" © 2007–2026 ShareX Team", size: small, color: .secondaryLabelColor)

        let licenseLink = Bundle.main.url(forResource: "LICENSE", withExtension: "txt")?.absoluteString
            ?? "https://www.gnu.org/licenses/gpl-3.0.html"
        append("\nFree software: redistribute or modify it under the ", size: footnote, color: .secondaryLabelColor)
        append("GNU GPL v3", size: footnote, link: licenseLink)
        append(".\u{2028}This program comes with ABSOLUTELY NO WARRANTY.", size: footnote, color: .secondaryLabelColor)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 7 // breathing room between the blocks
        credits.addAttributes([.paragraphStyle: paragraph],
                              range: NSRange(location: 0, length: credits.length))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc private func showSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: "SwiftX Settings", size: NSSize(width: 700, height: 460), view: AnyView(SettingsView()))
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
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        // swiftx://Verb/parameter reuses the CLI verb handler (workflows,
        // hotkey verbs, .sxcu/.sxie imports) — one dispatch path for both
        let args = CLIParser.arguments(fromURL: url)
        guard !args.isEmpty else {
            NSLog("SwiftX received URL with no verb: %@", urlString)
            return
        }
        Task { await CLI.handle(args) }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu == screensSubmenu {
            for screen in NSScreen.screens {
                let size = screen.frame.size
                let title = "\(screen.localizedName) (\(Int(size.width)) × \(Int(size.height)))"
                let item = NSMenuItem(title: title, action: #selector(captureScreenItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = screen
                menu.addItem(item)
            }
        } else if menu == windowsSubmenu {
            let windows = WindowLister.onScreenWindows(excludingPID: ProcessInfo.processInfo.processIdentifier)
            if windows.isEmpty {
                menu.addItem(NSMenuItem(title: "No capturable windows", action: nil, keyEquivalent: ""))
            }
            for window in windows {
                let item = NSMenuItem(title: String(window.menuTitle.prefix(60)),
                                      action: #selector(captureWindowItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = window
                menu.addItem(item)
            }
        }
    }
}
