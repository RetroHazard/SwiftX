// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Notification Center banners with the C# TaskSettingsGeneral granularity:
// a master off-switch, fullscreen suppression, per-event custom sounds and
// action buttons (Copy URL / Open, Show in Finder / Delete / Annotate).
// Custom sounds play through NSSound (UNNotificationSound would require
// copying files into ~/Library/Sounds); the banner itself goes out silent
// in that case so the sound isn't doubled.

import AppKit
import CaptureKit
import EditorKit
import Foundation
import SharedKit
import UserNotifications

@MainActor
enum Notifier {
    /// Which C# sound slot a notification belongs to.
    enum Event {
        case capture
        case taskCompleted
        case error
    }

    private static let delegate = NotifierDelegate()
    private static var pending: [UNNotificationRequest] = []
    private static var authorized: Bool?

    // Category / action identifiers for banner buttons.
    static let urlCategory = "swiftx.url"
    static let fileCategory = "swiftx.file"
    static let copyURLAction = "swiftx.copyURL"
    static let openURLAction = "swiftx.openURL"
    static let showFileAction = "swiftx.showFile"
    static let deleteFileAction = "swiftx.deleteFile"
    static let annotateFileAction = "swiftx.annotateFile"
    static let updateCategory = "swiftx.update"
    static let updateInstalledCategory = "swiftx.update.installed"
    static let installUpdateAction = "swiftx.installUpdate"
    static let viewReleaseAction = "swiftx.viewRelease"
    static let skipUpdateAction = "swiftx.skipUpdate"
    static let relaunchAction = "swiftx.relaunch"

    /// Call once at app launch: registers with Notification Center before any
    /// notification is posted, so nothing races the authorization prompt.
    static func setup() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: urlCategory,
                actions: [
                    UNNotificationAction(identifier: copyURLAction, title: "Copy URL"),
                    UNNotificationAction(identifier: openURLAction, title: "Open")
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: fileCategory,
                actions: [
                    UNNotificationAction(identifier: showFileAction, title: "Show in Finder"),
                    UNNotificationAction(identifier: annotateFileAction, title: "Annotate"),
                    UNNotificationAction(identifier: deleteFileAction, title: "Delete",
                                         options: [.destructive])
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: updateCategory,
                actions: [
                    UNNotificationAction(identifier: installUpdateAction, title: "Install Update"),
                    UNNotificationAction(identifier: viewReleaseAction, title: "View Release"),
                    UNNotificationAction(identifier: skipUpdateAction, title: "Skip This Version")
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: updateInstalledCategory,
                actions: [
                    UNNotificationAction(identifier: relaunchAction, title: "Relaunch")
                ],
                intentIdentifiers: []
            )
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            AppLog.notifications.info("Authorization result: granted=\(granted) error=\(error?.localizedDescription ?? "none", privacy: .public)")
            Task { @MainActor in
                authorized = granted
                let queued = pending
                pending.removeAll()
                if granted {
                    queued.forEach(post)
                }
            }
        }
    }

    static func captureSaved(_ url: URL) {
        notify(title: "Screenshot captured", body: url.lastPathComponent,
               sound: TaskSettings.load().playSoundAfterCapture, filePath: url.path, event: .capture)
    }

    /// Clicking the banner opens `url` when set, otherwise reveals `filePath`.
    static func notify(title: String, body: String, sound: Bool = false,
                       url: String? = nil, filePath: String? = nil,
                       event: Event = .taskCompleted) {
        guard Bundle.main.bundleIdentifier != nil else {
            AppLog.notifications.info("\(title, privacy: .public): \(body, privacy: .public)")
            return
        }
        let settings = TaskSettings.load()

        // C# ShowToastNotificationAfterTaskCompleted: banners off, sounds stay
        let suppressed = !settings.showToastNotificationAfterTaskCompleted
            || (settings.disableNotificationsOnFullscreen && FullscreenDetector.frontmostAppIsFullscreen())

        var playedCustomSound = false
        if sound, let custom = customSound(for: event, settings: settings) {
            custom.play()
            playedCustomSound = true
        }
        if suppressed {
            AppLog.notifications.info("Suppressed (settings): \(title, privacy: .public) - \(body, privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound, !playedCustomSound {
            content.sound = .default
        }
        if let url {
            content.userInfo["url"] = url
            content.categoryIdentifier = urlCategory
        } else if filePath != nil {
            content.categoryIdentifier = fileCategory
        }
        if let filePath { content.userInfo["filePath"] = filePath }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        switch authorized {
        case .none:
            pending.append(request) // authorization still resolving; deliver after
        case .some(true):
            post(request)
        case .some(false):
            AppLog.notifications.info("Suppressed (not authorized): \(title, privacy: .public) - \(body, privacy: .public)")
        }
    }

    /// App-lifecycle notice, not a task banner: skips the C#
    /// ShowToastNotificationAfterTaskCompleted master switch (fullscreen
    /// suppression still applies - an update can wait out a presentation).
    static func notifyUpdate(title: String, body: String, version: String, url: String,
                             installed: Bool) {
        guard Bundle.main.bundleIdentifier != nil else {
            AppLog.updates.info("\(title, privacy: .public): \(body, privacy: .public)")
            return
        }
        let settings = TaskSettings.load()
        if settings.disableNotificationsOnFullscreen, FullscreenDetector.frontmostAppIsFullscreen() {
            AppLog.updates.info("update banner suppressed (fullscreen): \(title, privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = installed ? updateInstalledCategory : updateCategory
        content.userInfo["url"] = url
        content.userInfo["updateVersion"] = version
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        switch authorized {
        case .none:
            pending.append(request)
        case .some(true):
            post(request)
        case .some(false):
            AppLog.updates.info("update banner suppressed (not authorized): \(title, privacy: .public)")
        }
    }

    /// C# UseCustom*Sound/Custom*SoundPath per event slot.
    private static func customSound(for event: Event, settings: TaskSettings) -> NSSound? {
        let path: String? = switch event {
        case .capture where settings.useCustomCaptureSound:
            settings.customCaptureSoundPath
        case .taskCompleted where settings.useCustomTaskCompletedSound:
            settings.customTaskCompletedSoundPath
        case .error where settings.useCustomErrorSound:
            settings.customErrorSoundPath
        default:
            nil
        }
        guard let path, !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        return NSSound(contentsOfFile: path, byReference: true)
    }

    private static func post(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.notifications.error("Delivery failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// C# DisableNotificationsOnFullscreen / DisableHotkeysOnFullscreen helper:
/// treats the frontmost app as fullscreen when one of its layer-0 windows
/// exactly covers a screen. Window bounds via CGWindowList need no TCC
/// permission (only titles/contents do).
enum FullscreenDetector {
    static func frontmostAppIsFullscreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let screenFrames = NSScreen.screens.map { screen in
            // CGWindowList bounds are CG-global (top-left origin)
            CGRect(x: screen.frame.minX,
                   y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }
            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            if screenFrames.contains(where: { $0 == bounds }) {
                return true
            }
        }
        return false
    }
}

/// Without this delegate, macOS suppresses banners while the posting app is
/// frontmost - which SwiftX often is right after the region overlay activates it.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let urlString = info["url"] as? String
        let path = info["filePath"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case Notifier.copyURLAction:
                if let urlString {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(urlString, forType: .string)
                }
            case Notifier.openURLAction:
                if let urlString, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            case Notifier.showFileAction:
                if let path, FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            case Notifier.deleteFileAction:
                if let path {
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                }
            case Notifier.annotateFileAction:
                if let path { Self.annotate(path: path) }
            case Notifier.installUpdateAction:
                UpdateManager.shared.installCurrentUpdate()
            case Notifier.viewReleaseAction:
                UpdateManager.shared.openReleasePage()
            case Notifier.skipUpdateAction:
                UpdateManager.shared.skipCurrentUpdate()
            case Notifier.relaunchAction:
                UpdateManager.shared.relaunchNow()
            default:
                // banner tap: open URL, else reveal the file (original behavior)
                if let urlString, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                } else if let path, FileManager.default.fileExists(atPath: path) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
        }
    }

    /// "Annotate" banner button: edit the file in place.
    @MainActor
    private static func annotate(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let image = NSImage(contentsOf: url)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        Task {
            guard let edited = await ImageEditorPresenter.present(image: image) else { return }
            let format = ImageFileFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() }
                ?? .png
            try? ImageWriter.write(edited, to: url, format: format)
        }
    }
}
