// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Synchronous window enumeration for the window-picker menu. CGWindowList
// works inside NSMenuDelegate.menuNeedsUpdate, where the async
// SCShareableContent cannot; the picked ID is then captured via
// ScreenCaptureKit. Window titles require Screen Recording permission.

import CoreGraphics
import Foundation

public struct CapturableWindow: Sendable {
    public let id: CGWindowID
    public let ownerName: String
    public let title: String

    public var menuTitle: String {
        title.isEmpty || title == ownerName ? ownerName : "\(ownerName) — \(title)"
    }
}

public enum WindowLister {
    /// On-screen, normal-layer windows big enough to be worth capturing,
    /// front-to-back. Pass the current process ID to hide ShareX's own windows.
    public static func onScreenWindows(excludingPID: pid_t? = nil) -> [CapturableWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer] as? Int) == 0,
                  let id = info[kCGWindowNumber] as? Int,
                  let owner = info[kCGWindowOwnerName] as? String, !owner.isEmpty,
                  (info[kCGWindowOwnerPID] as? pid_t) != excludingPID,
                  let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                  bounds["Width", default: 0] >= 50, bounds["Height", default: 0] >= 50
            else { return nil }
            return CapturableWindow(id: CGWindowID(id), ownerName: owner,
                                    title: info[kCGWindowName] as? String ?? "")
        }
    }
}
