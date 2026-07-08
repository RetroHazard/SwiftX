// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import UserNotifications

@MainActor
enum Notifier {
    private static let delegate = NotifierDelegate()
    private static var pending: [UNNotificationRequest] = []
    private static var authorized: Bool?

    /// Call once at app launch: registers with Notification Center before any
    /// notification is posted, so nothing races the authorization prompt.
    static func setup() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            NSLog("Notification authorization result: granted=%d error=%@", granted,
                  error?.localizedDescription ?? "none")
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
        notify(title: "Screenshot captured", body: url.lastPathComponent)
    }

    static func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("%@: %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

        switch authorized {
        case .none:
            pending.append(request) // authorization still resolving; deliver after
        case .some(true):
            post(request)
        case .some(false):
            NSLog("Notification suppressed (not authorized): %@ - %@", title, body)
        }
    }

    private static func post(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Notification delivery failed: %@", error.localizedDescription)
            }
        }
    }
}

/// Without this delegate, macOS suppresses banners while the posting app is
/// frontmost - which ShareX often is right after the region overlay activates it.
final class NotifierDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
