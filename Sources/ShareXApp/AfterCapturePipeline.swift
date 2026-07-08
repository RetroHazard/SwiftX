// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Runs the configured AfterCaptureTasks chain on a captured image.
// Unimplemented flags log and no-op until their phase lands (editor,
// effects, OCR, upload, ...).

import AppKit
import CaptureKit
import SharedKit

@MainActor
enum AfterCapturePipeline {
    static let implemented: AfterCaptureTasks = [
        .copyImageToClipboard, .pinToScreen, .saveImageToFile, .saveImageToFileWithDialog,
        .copyFilePathToClipboard, .copyFolderPathToClipboard, .showInExplorer
    ]

    static func run(image: CGImage, processName: String? = nil, windowTitle: String? = nil) {
        let settings = TaskSettings.load()
        let config = ApplicationConfig.load()
        let tasks = settings.afterCaptureJob

        if tasks.contains(.copyImageToClipboard) {
            ImageWriter.copyToClipboard(image)
        }

        if tasks.contains(.pinToScreen) {
            PinnedWindows.pin(image)
        }

        var savedURL: URL?

        if tasks.contains(.saveImageToFile) {
            let url = SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: image.width, height: image.height
            )
            do {
                try ImageWriter.writePNG(image, to: url)
                savedURL = url
                Notifier.captureSaved(url)
            } catch {
                presentError(error)
            }
        }

        if tasks.contains(.saveImageToFileWithDialog) {
            let panel = NSSavePanel()
            panel.directoryURL = config.screenshotsFolder
            panel.nameFieldStringValue = savedURL?.lastPathComponent
                ?? SavePath.screenshotURL(config: config, task: settings, processName: processName).lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try ImageWriter.writePNG(image, to: url)
                    savedURL = url
                } catch {
                    presentError(error)
                }
            }
        }

        if let savedURL {
            if tasks.contains(.copyFilePathToClipboard) {
                copyString(savedURL.path)
            }
            if tasks.contains(.copyFolderPathToClipboard) {
                copyString(savedURL.deletingLastPathComponent().path)
            }
            if tasks.contains(.showInExplorer) {
                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
            }
        }

        let pending = tasks.subtracting(implemented)
        if !pending.isEmpty {
            NSLog("AfterCaptureTasks not implemented yet: %@", pending.nameString)
        }
    }

    private static func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "After-capture task failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

/// Floating always-on-top image windows ("Pin to screen").
/// Drag to move, double-click to close.
@MainActor
enum PinnedWindows {
    private static var panels: [NSPanel] = []

    static func pin(_ cgImage: CGImage) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        pin(NSImage(cgImage: cgImage, size: size))
    }

    static func pin(_ image: NSImage) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        var size = image.size
        if let screen = NSScreen.main {
            let maxSize = NSSize(width: screen.visibleFrame.width * 0.6, height: screen.visibleFrame.height * 0.6)
            let ratio = min(1, maxSize.width / size.width, maxSize.height / size.height)
            size = NSSize(width: size.width * ratio, height: size.height * ratio)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        let doubleClick = NSClickGestureRecognizer(target: panel, action: #selector(NSPanel.close))
        doubleClick.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClick)
        panel.contentView = imageView

        panel.center()
        panel.orderFrontRegardless()
        panels.append(panel)
    }

    static func pinFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            Notifier.notify(title: "Pin to screen", body: "No image on the clipboard.")
            return
        }
        pin(image)
    }

    static func closeAll() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}
