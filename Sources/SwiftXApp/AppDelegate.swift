// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE

import AppKit
import CaptureKit
import Combine
import EffectsKit
import HistoryKit
import SwiftUI
import SharedKit
import UploadKit
import UserNotifications

/// Hideable status-bar menu entries (ApplicationConfig.trayMenuHiddenItems).
/// Settings… and Quit are deliberately absent — hiding them would strand the
/// user with no way back into the app.
enum TrayMenuItemID: String, CaseIterable {
    case captureRegion = "CaptureRegion"
    case captureFullScreen = "CaptureFullScreen"
    case captureActiveWindow = "CaptureActiveWindow"
    case captureScreen = "CaptureScreen"
    case captureWindow = "CaptureWindow"
    case captureLastRegion = "CaptureLastRegion"
    case scrollingCapture = "ScrollingCapture"
    case autoCapture = "AutoCapture"
    case screenshotDelay = "ScreenshotDelay"
    case recording = "Recording"
    case upload = "Upload"
    case tools = "Tools"
    case recent = "Recent"
    case mainWindow = "MainWindow"
    case log = "Log"

    var displayName: String {
        switch self {
        case .captureRegion: return "Capture Region"
        case .captureFullScreen: return "Capture Full Screen"
        case .captureActiveWindow: return "Capture Active Window"
        case .captureScreen: return "Capture Screen…"
        case .captureWindow: return "Capture Window…"
        case .captureLastRegion: return "Capture Last Region"
        case .scrollingCapture: return "Scrolling Capture…"
        case .autoCapture: return "Auto Capture…"
        case .screenshotDelay: return "Screenshot Delay"
        case .recording: return "Recording"
        case .upload: return "Upload"
        case .tools: return "Tools"
        case .recent: return "Recent"
        case .mainWindow: return "Main Window…"
        case .log: return "Show Log…"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var recordItem: NSMenuItem?
    private var recordGIFItem: NSMenuItem?
    private var pauseRecordingItem: NSMenuItem?
    private var abortRecordingItem: NSMenuItem?
    private let screensSubmenu = NSMenu()
    private let windowsSubmenu = NSMenu()
    private let delaySubmenu = NSMenu()
    private let uploadSubmenu = NSMenu()
    private let recentSubmenu = NSMenu()
    private var uploadProgressCancellable: AnyCancellable?
    /// Receives "Upload with SwiftX" service invocations (kept strongly:
    /// NSApp.servicesProvider is unretained).
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = StatusIcon.idle
        // No permanent menu: left click runs the configured action
        // (C# TrayLeftClickAction), right click always opens the menu.
        statusMenu = buildMenu()
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self
        statusItem = item

        // C# TrayIconProgressEnabled: live upload progress in the status icon
        uploadProgressCancellable = UploadTaskCenter.shared.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] entries in self?.updateUploadProgressIcon(entries) }

        if ApplicationConfig.load().actionsToolbarRunAtStartup {
            ActionsToolbar.show()
        }

        // watermark text (%h, %mi, ...) runs through the ShareX pattern parser
        EffectsEnvironment.textParser = { NameParser(.text).parse($0) }

        // "Upload with SwiftX" in the system-wide Services context menu; the
        // service definition lives in Info.plist (only present in .app builds)
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()

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
                AppLog.app.debug("upload-test pasteboard: \(NSPasteboard.general.string(forType: .string) ?? "<empty>", privacy: .public)")
            }
        }

        if CommandLine.arguments.contains("--notify-test") {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                AppLog.notifications.debug("Notification settings: authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue)")
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

    /// Builds the status menu, skipping entries the user hid in Settings →
    /// General → Menu bar. Rebuilt on every open so edits apply immediately.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let hidden = Set(ApplicationConfig.load().trayMenuHiddenItems)
        func visible(_ id: TrayMenuItemID) -> Bool { !hidden.contains(id.rawValue) }

        if visible(.captureRegion) {
            menu.addItem(NSMenuItem(title: "Capture Region", action: #selector(captureRegion), keyEquivalent: ""))
        }
        if visible(.captureFullScreen) {
            menu.addItem(NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: ""))
        }
        if visible(.captureActiveWindow) {
            menu.addItem(NSMenuItem(title: "Capture Active Window", action: #selector(captureActiveWindow), keyEquivalent: ""))
        }

        // pickers populate on open: displays and windows change constantly
        screensSubmenu.delegate = self
        windowsSubmenu.delegate = self
        if visible(.captureScreen) {
            let screenPicker = NSMenuItem(title: "Capture Screen…", action: nil, keyEquivalent: "")
            screenPicker.submenu = screensSubmenu
            menu.addItem(screenPicker)
        }
        if visible(.captureWindow) {
            let windowPicker = NSMenuItem(title: "Capture Window…", action: nil, keyEquivalent: "")
            windowPicker.submenu = windowsSubmenu
            menu.addItem(windowPicker)
        }
        if visible(.captureLastRegion) {
            menu.addItem(NSMenuItem(title: "Capture Last Region", action: #selector(captureLastRegion), keyEquivalent: ""))
        }
        if visible(.scrollingCapture) {
            menu.addItem(NSMenuItem(title: "Scrolling Capture…", action: #selector(showScrollingCapture), keyEquivalent: ""))
        }
        if visible(.autoCapture) {
            menu.addItem(NSMenuItem(title: "Auto Capture…", action: #selector(showAutoCapture), keyEquivalent: ""))
        }
        // C# tray "screenshot delay" selector; applies to every capture verb
        delaySubmenu.delegate = self
        if visible(.screenshotDelay) {
            let delayPicker = NSMenuItem(title: "Screenshot Delay", action: nil, keyEquivalent: "")
            delayPicker.submenu = delaySubmenu
            menu.addItem(delayPicker)
        }

        // hiding "Recording" hides the start verbs, never the live recording
        // controls — a running recording must stay stoppable from the menu
        menu.addItem(.separator())
        let record = NSMenuItem(title: "Record Screen (Region)…", action: #selector(toggleRecording), keyEquivalent: "")
        let recordGIF = NSMenuItem(title: "Record GIF (Region)…", action: #selector(toggleGIFRecording), keyEquivalent: "")
        let recording = RecordingCoordinator.shared.isRecording
        record.isHidden = !visible(.recording) && !recording
        recordGIF.isHidden = !visible(.recording)
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
        // C# tray Upload section; populated on open so the Disable checkmark is live
        uploadSubmenu.delegate = self
        if visible(.upload) {
            let upload = NSMenuItem(title: "Upload", action: nil, keyEquivalent: "")
            upload.submenu = uploadSubmenu
            menu.addItem(upload)
        }

        if visible(.tools) {
            let tools = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
            tools.submenu = buildToolsMenu()
            menu.addItem(tools)
        }

        // C# RecentTasksShowInTrayMenu: last N history entries
        recentSubmenu.delegate = self
        if visible(.recent) {
            let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            recent.submenu = recentSubmenu
            menu.addItem(recent)
        }

        menu.addItem(.separator())
        if visible(.mainWindow) {
            menu.addItem(NSMenuItem(title: "Main Window…", action: #selector(showMainWindow), keyEquivalent: ""))
        }
        if visible(.log) {
            menu.addItem(NSMenuItem(title: "Show Log…", action: #selector(showLog), keyEquivalent: ""))
        }
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsWindow), keyEquivalent: ",")
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SwiftX", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // only claim selectors we implement; the rest (e.g. terminate) stay
        // targetless so the responder chain delivers them to NSApp
        menu.items.forEach { $0.target = $0.action.map(responds(to:)) == true ? self : nil }
        pruneSeparators(menu)
        return menu
    }

    /// Hidden entries can leave doubled or leading separators behind; AppKit
    /// only collapses them in some contexts, so tidy explicitly. Items that are
    /// merely hidden (the dormant recording controls) count as absent.
    private func pruneSeparators(_ menu: NSMenu) {
        var previousWasSeparator = true // drops a leading separator too
        var index = 0
        while index < menu.items.count {
            let item = menu.items[index]
            if item.isHidden {
                index += 1 // invisible: does not break up a separator run
            } else if item.isSeparatorItem {
                if previousWasSeparator {
                    menu.removeItem(at: index)
                } else {
                    previousWasSeparator = true
                    index += 1
                }
            } else {
                previousWasSeparator = false
                index += 1
            }
        }
        while let last = menu.items.last(where: { !$0.isHidden }), last.isSeparatorItem {
            menu.removeItem(last)
        }
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
            ("Background Remover…", .backgroundRemover),
            ("Image Comparer…", .imageComparer),
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

    @objc private func setScreenshotDelay(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        var settings = TaskSettings.load()
        settings.screenshotDelay = seconds
        try? settings.save()
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
        RecordingCoordinator.shared.confirmAbort()
    }

    @objc private func togglePauseRecording() {
        RecordingCoordinator.shared.togglePause()
    }

    private func updateRecordingUI() {
        let recording = RecordingCoordinator.shared.isRecording
        let startVerbsVisible = !ApplicationConfig.load().trayMenuHiddenItems
            .contains(TrayMenuItemID.recording.rawValue)
        recordItem?.title = recording ? "Stop Recording" : "Record Screen (Region)…"
        recordItem?.isHidden = !startVerbsVisible && !recording
        recordGIFItem?.isHidden = recording || !startVerbsVisible
        pauseRecordingItem?.isHidden = !recording
        pauseRecordingItem?.title = RecordingCoordinator.shared.isPaused ? "Resume Recording" : "Pause Recording"
        abortRecordingItem?.isHidden = !recording
        statusItem?.button?.image = recording
            ? NSImage(systemSymbolName: "record.circle", accessibilityDescription: "SwiftX recording")
            : StatusIcon.idle
        statusItem?.button?.contentTintColor = recording ? .systemRed : nil
    }

    /// ToggleTrayMenu hotkey: pops the status-item menu open.
    func toggleStatusMenu() {
        showStatusMenu()
    }

    @objc private func statusItemClicked() {
        let leftAction = ApplicationConfig.load().trayLeftClickAction
        if NSApp.currentEvent?.type == .rightMouseUp
            || leftAction == "ToggleTrayMenu"
            || HotkeyType(rawValue: leftAction) == nil {
            showStatusMenu()
        } else {
            HotkeyDispatcher.execute(HotkeyType(rawValue: leftAction)!)
        }
    }

    /// Attach the menu just for the click, then detach so the next left click
    /// reaches statusItemClicked again (standard custom-click pattern).
    /// Rebuilt every open so menu-item visibility edits apply immediately.
    private func showStatusMenu() {
        guard let statusItem else { return }
        statusMenu = buildMenu()
        updateRecordingUI()
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func updateUploadProgressIcon(_ entries: [UploadTaskCenter.Entry]) {
        // the recording indicator owns the icon while a recording runs
        guard !RecordingCoordinator.shared.isRecording else { return }
        let uploading = entries.filter { $0.state == .uploading || $0.state == .retrying }
        if ApplicationConfig.load().trayIconProgressEnabled, !uploading.isEmpty {
            let fraction = uploading.map(\.fraction).reduce(0, +) / Double(uploading.count)
            statusItem?.button?.image = StatusIcon.progress(fraction)
        } else {
            statusItem?.button?.image = StatusIcon.idle
        }
    }

    @objc private func toggleDisableUploads() {
        var config = ApplicationConfig.load()
        config.disableUpload.toggle()
        try? config.save()
    }

    /// Recent submenu click: copy the URL when one exists, else reveal the file.
    @objc private func recentItemClicked(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url, forType: .string)
        } else if let fileURL = sender.representedObject as? URL {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    @objc private func showLog() {
        ToolWindows.showLog()
    }

    @objc func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeWindow(title: "SwiftX", size: NSSize(width: 640, height: 420), view: AnyView(MainWindowView()))
        }
        present(mainWindow)
    }

    @objc func showSettingsWindow() {
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
            AppLog.app.warning("Received URL with no verb: \(urlString, privacy: .public)")
            return
        }
        // Any web page can open a swiftx:// URL, so this is untrusted input:
        // file-touching verbs are confirmed or blocked inside CLI.handle.
        Task { await CLI.handle(args, source: .untrusted) }
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
        } else if menu == uploadSubmenu {
            let verbs: [(String, HotkeyType)] = [
                ("Upload File…", .fileUpload),
                ("Upload Folder…", .folderUpload),
                ("Upload from Clipboard", .clipboardUpload),
                ("Upload Text…", .uploadText),
                ("Upload URL…", .uploadURL),
                ("Shorten URL…", .shortenURL),
                ("Drop Window", .dragDropUpload)
            ]
            for (title, type) in verbs {
                let item = NSMenuItem(title: title, action: #selector(toolMenuAction(_:)), keyEquivalent: "")
                item.representedObject = type.rawValue
                item.target = self
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let stop = NSMenuItem(title: "Stop All Uploads", action: #selector(toolMenuAction(_:)), keyEquivalent: "")
            stop.representedObject = HotkeyType.stopUploads.rawValue
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
            let disable = NSMenuItem(title: "Disable Uploads", action: #selector(toggleDisableUploads), keyEquivalent: "")
            disable.target = self
            disable.state = ApplicationConfig.load().disableUpload ? .on : .off
            menu.addItem(disable)
        } else if menu == recentSubmenu {
            let config = ApplicationConfig.load()
            guard config.recentTasksShowInTrayMenu else {
                menu.addItem(NSMenuItem(title: "Disabled in Settings", action: nil, keyEquivalent: ""))
                return
            }
            let items = HistoryStore.shared.recent(limit: max(1, config.recentTasksMaxCount))
            if items.isEmpty {
                menu.addItem(NSMenuItem(title: "No recent tasks", action: nil, keyEquivalent: ""))
            }
            for entry in items {
                let name = entry.fileName.isEmpty
                    ? (entry.url.isEmpty ? entry.filePath : entry.url) : entry.fileName
                let item = NSMenuItem(title: String(name.prefix(60)),
                                      action: #selector(recentItemClicked(_:)), keyEquivalent: "")
                item.target = self
                if !entry.url.isEmpty {
                    item.representedObject = entry.url
                    item.toolTip = "Copy \(entry.url)"
                } else if !entry.filePath.isEmpty {
                    item.representedObject = URL(fileURLWithPath: entry.filePath)
                    item.toolTip = "Show in Finder"
                }
                menu.addItem(item)
            }
        } else if menu == delaySubmenu {
            let current = TaskSettings.load().screenshotDelay
            for seconds in [0.0, 1, 2, 3, 4, 5] {
                let title = seconds == 0 ? "Off" : "\(Int(seconds)) Second\(seconds == 1 ? "" : "s")"
                let item = NSMenuItem(title: title, action: #selector(setScreenshotDelay(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = seconds
                item.state = abs(current - seconds) < 0.001 ? .on : .off
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
