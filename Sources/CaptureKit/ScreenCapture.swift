// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import AppKit
import ScreenCaptureKit

public enum ScreenCaptureError: LocalizedError {
    case noDisplay
    case noWindow
    case cropFailed

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found for the capture area."
        case .noWindow: return "No capturable window found for the frontmost app."
        case .cropFailed: return "Failed to crop the captured image."
        }
    }
}

public enum ScreenCapture {
    /// Captures a full display. Defaults to the display containing the mouse cursor.
    public static func captureDisplay(screen: NSScreen? = nil, showsCursor: Bool = true) async throws -> CGImage {
        let target = screen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let target else { throw ScreenCaptureError.noDisplay }
        let content = try await shareableContent()
        return try await captureImage(of: try scDisplay(for: target, in: content),
                                      scale: target.backingScaleFactor,
                                      showsCursor: showsCursor)
    }

    /// Captures a region given in Cocoa global coordinates (bottom-left origin, y-up).
    /// Selections spanning multiple displays are stitched into one image at the
    /// highest backing scale among the displays; uncovered gaps stay transparent.
    public static func captureRegion(cocoaRect: CGRect, showsCursor: Bool = false) async throws -> CGImage {
        let screens = NSScreen.screens.filter { $0.frame.intersects(cocoaRect) }
        guard !screens.isEmpty else { throw ScreenCaptureError.noDisplay }
        let content = try await shareableContent()

        if screens.count == 1 {
            return try await captureRegionCrop(cocoaRect, on: screens[0], in: content, showsCursor: showsCursor)
        }

        let scale = screens.map(\.backingScaleFactor).max()!
        guard let context = CGContext(
            data: nil,
            width: Int(cocoaRect.width * scale), height: Int(cocoaRect.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ScreenCaptureError.cropFailed }
        context.interpolationQuality = .high

        for screen in screens {
            let part = cocoaRect.intersection(screen.frame)
            let image = try await captureRegionCrop(part, on: screen, in: content, showsCursor: showsCursor)
            // context origin is bottom-left, same as Cocoa global — no flip needed
            context.draw(image, in: CGRect(x: (part.minX - cocoaRect.minX) * scale,
                                           y: (part.minY - cocoaRect.minY) * scale,
                                           width: part.width * scale,
                                           height: part.height * scale))
        }
        guard let stitched = context.makeImage() else { throw ScreenCaptureError.cropFailed }
        return stitched
    }

    /// Captures one display and crops out the given Cocoa-global rect (clamped to that display).
    private static func captureRegionCrop(_ cocoaRect: CGRect, on screen: NSScreen,
                                          in content: SCShareableContent,
                                          showsCursor: Bool) async throws -> CGImage {
        let clamped = cocoaRect.intersection(screen.frame)
        let scale = screen.backingScaleFactor
        let full = try await captureImage(of: try scDisplay(for: screen, in: content), scale: scale, showsCursor: showsCursor)
        let pixelRect = ScreenCoordinates.displayLocalPixelRect(of: clamped, in: screen.frame, scale: scale)
        guard let cropped = full.cropping(to: pixelRect.integral) else { throw ScreenCaptureError.cropFailed }
        return cropped
    }

    /// Captures the largest on-screen window of the frontmost application.
    /// Sample the frontmost app BEFORE presenting any SwiftX UI.
    public static func captureFrontmostWindow(processID: pid_t? = nil, showsCursor: Bool = false) async throws -> CGImage {
        let pid = processID ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pid else { throw ScreenCaptureError.noWindow }

        let content = try await shareableContent()
        let window = content.windows
            .filter { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 }
            .max { $0.frame.area < $1.frame.area }
        guard let window else { throw ScreenCaptureError.noWindow }
        return try await captureImage(of: window, showsCursor: showsCursor)
    }

    /// Captures a specific window picked from the window list.
    public static func captureWindow(windowID: CGWindowID, showsCursor: Bool = false) async throws -> CGImage {
        let content = try await shareableContent()
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.noWindow
        }
        return try await captureImage(of: window, showsCursor: showsCursor)
    }

    private static func captureImage(of window: SCWindow, showsCursor: Bool = false) async throws -> CGImage {
        // window.frame is in CG global points (top-left origin)
        let scale = NSScreen.screens
            .first { ScreenCoordinates.cgFromCocoa($0.frame).intersects(window.frame) }?
            .backingScaleFactor ?? 2

        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: configuration
        )
    }

    // MARK: - Internals

    private static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private static func scDisplay(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw ScreenCaptureError.noDisplay
        }
        return display
    }

    private static func captureImage(of display: SCDisplay, scale: CGFloat, showsCursor: Bool) async throws -> CGImage {
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.showsCursor = showsCursor
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []),
            configuration: configuration
        )
    }
}

public enum ScreenCoordinates {
    /// Cocoa global (bottom-left origin, y-up) -> CoreGraphics global (top-left origin, y-down).
    public static func cgFromCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cgFromCocoa(_ rect: CGRect) -> CGRect {
        cgFromCocoa(rect, primaryHeight: NSScreen.screens.first?.frame.maxY ?? 0)
    }

    /// CG global -> Cocoa global. The flip is its own inverse.
    public static func cocoaFromCG(_ rect: CGRect) -> CGRect {
        cgFromCocoa(rect)
    }

    /// Cocoa-global rect -> pixel rect local to a screen (top-left origin), for cropping captured images.
    public static func displayLocalPixelRect(of rect: CGRect, in screenFrame: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: (rect.minX - screenFrame.minX) * scale,
            y: (screenFrame.maxY - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}
