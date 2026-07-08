// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import UserNotifications

@MainActor
enum Notifier {
    private static var authorizationRequested = false

    static func captureSaved(_ url: URL) {
        notify(title: "Screenshot captured", body: url.lastPathComponent)
    }

    static func notify(title: String, body: String) {
        // UNUserNotificationCenter traps outside an app bundle (bare `swift run`)
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("%@: %@", title, body)
            return
        }
        let center = UNUserNotificationCenter.current()
        if !authorizationRequested {
            authorizationRequested = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
