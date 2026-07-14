// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Runs the configured AfterCaptureTasks chain on a captured image.
// Unimplemented flags log and no-op until their phase lands (editor,
// effects, OCR, upload, ...).

import AppKit
import CaptureKit
import EditorKit
import EffectsKit
import HistoryKit
import SharedKit
import ToolsKit

@MainActor
enum AfterCapturePipeline {
    static let implemented: AfterCaptureTasks = [
        .showQuickTaskMenu, .showAfterCaptureWindow, .showBeforeUploadWindow,
        .beautifyImage, .addImageEffects,
        .annotateImage, .copyImageToClipboard, .pinToScreen, .sendImageToPrinter,
        .saveImageToFile, .saveImageToFileWithDialog, .saveThumbnailImageToFile,
        .performActions, .copyFileToClipboard, .copyFilePathToClipboard, .copyFolderPathToClipboard,
        .showInExplorer, .analyzeImage, .scanQRCode, .doOCR, .uploadImageToHost, .deleteFile
    ]

    /// `settings` overrides the stored TaskSettings (auto capture strips the
    /// interactive steps); `quiet` drops the capture banner (C# auto-capture
    /// suppresses toasts).
    static func run(image capturedImage: CGImage, processName: String? = nil, windowTitle: String? = nil,
                    settings settingsOverride: TaskSettings? = nil, quiet: Bool = false) async {
        var settings = settingsOverride ?? TaskSettings.load()
        let config = ApplicationConfig.load()

        if settings.afterCaptureJob.contains(.showQuickTaskMenu) {
            switch QuickTaskMenu.choose() {
            case .cancel:
                return
            case .continueChain:
                settings.afterCaptureJob.remove(.showQuickTaskMenu)
            case .preset(let preset):
                // C#: the preset replaces both task chains for this run only
                settings.afterCaptureJob = preset.afterCaptureTasks
                settings.afterUploadJob = preset.afterUploadTasks
            }
        }

        var fileNameOverride: String?
        if settings.afterCaptureJob.contains(.showAfterCaptureWindow) {
            let defaultName = SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: capturedImage.width, height: capturedImage.height,
                fileExtension: "png"
            ).deletingPathExtension().lastPathComponent
            switch await AfterCaptureWindow.present(image: capturedImage, settings: settings,
                                                    defaultFileName: defaultName) {
            case .cancel:
                return
            case .proceed(let edited, let fileName):
                settings = edited
                settings.afterCaptureJob.remove(.showAfterCaptureWindow)
                if !fileName.isEmpty, fileName != defaultName {
                    fileNameOverride = fileName
                }
            }
        }
        let tasks = settings.afterCaptureJob

        var image = capturedImage
        // C# task order: beautify, then effects, then the editor
        if tasks.contains(.beautifyImage) {
            image = ImageBeautifier.render(image, options: ImageEffectsStore.shared.beautifier)
        }
        if tasks.contains(.addImageEffects), let preset = ImageEffectsStore.shared.selectedPreset {
            image = preset.apply(image)
        }
        if tasks.contains(.annotateImage) {
            // C# behavior: the task waits for the editor; Cancel aborts the whole task
            guard let edited = await ImageEditorPresenter.present(image: image) else { return }
            image = edited
        }

        if tasks.contains(.copyImageToClipboard) {
            ImageWriter.copyToClipboard(image)
        }

        if tasks.contains(.pinToScreen) {
            PinnedWindows.pin(image)
        }

        let format = ImageWriter.effectiveFormat(
            named: settings.imageFormat,
            autoUseJPEG: settings.imageAutoUseJPEG, autoUseJPEGSize: settings.imageAutoUseJPEGSize,
            width: image.width, height: image.height
        )
        var savedURL: URL?

        // after-capture window edits replace the generated name (same folder)
        func withNameOverride(_ url: URL) -> URL {
            guard let fileNameOverride else { return url }
            return url.deletingLastPathComponent()
                .appendingPathComponent(fileNameOverride)
                .appendingPathExtension(format.fileExtension)
        }

        if tasks.contains(.saveImageToFile) {
            let url = withNameOverride(SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: image.width, height: image.height,
                fileExtension: format.fileExtension
            ))
            do {
                try ImageWriter.write(image, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
                savedURL = url
                if !quiet { Notifier.captureSaved(url) }
            } catch {
                presentError(error)
            }
        }

        if tasks.contains(.saveImageToFileWithDialog) {
            let panel = NSSavePanel()
            panel.directoryURL = config.screenshotsFolder
            panel.nameFieldStringValue = savedURL?.lastPathComponent
                ?? withNameOverride(SavePath.screenshotURL(config: config, task: settings, processName: processName,
                                                           fileExtension: format.fileExtension)).lastPathComponent
            NSApp.activate(ignoringOtherApps: true)
            if panel.runModal() == .OK, let url = panel.url {
                do {
                    try ImageWriter.write(image, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
                    savedURL = url
                } catch {
                    presentError(error)
                }
            }
        }

        if tasks.contains(.saveThumbnailImageToFile),
           let thumb = ImageWriter.thumbnail(image, width: settings.thumbnailWidth,
                                             height: settings.thumbnailHeight,
                                             onlyIfLarger: settings.thumbnailCheckSize) {
            let base = savedURL ?? withNameOverride(SavePath.screenshotURL(
                config: config, task: settings,
                windowTitle: windowTitle, processName: processName,
                width: image.width, height: image.height,
                fileExtension: format.fileExtension
            ))
            let name = base.deletingPathExtension().lastPathComponent + settings.thumbnailName
            let url = base.deletingLastPathComponent()
                .appendingPathComponent(name).appendingPathExtension(format.fileExtension)
            do {
                try ImageWriter.write(thumb, to: url, format: format, jpegQuality: settings.imageJPEGQuality)
            } catch {
                presentError(error)
            }
        }

        // actions run before anything references the file, so the pipeline
        // continues with the action's output (C# order: actions precede upload)
        if tasks.contains(.performActions), let inputURL = savedURL {
            do {
                savedURL = try await ExternalProgramRunner.runAll(settings.externalPrograms, on: inputURL)
            } catch {
                Notifier.notify(title: "Action failed", body: error.localizedDescription)
            }
        }

        if let savedURL {
            var historyItem = HistoryItem()
            historyItem.fileName = savedURL.lastPathComponent
            historyItem.filePath = savedURL.path
            historyItem.type = "Image"
            historyItem.host = "File"
            // same tags C# TaskMetadata records; the history search matches them
            if let windowTitle, !windowTitle.isEmpty { historyItem.tags["WindowTitle"] = windowTitle }
            if let processName, !processName.isEmpty { historyItem.tags["ProcessName"] = processName }
            HistoryStore.shared.append(historyItem)

            if tasks.contains(.copyFileToClipboard) {
                // file reference, not pixels: pasting in Finder/Slack attaches the file
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([savedURL as NSURL])
            }
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

        if tasks.contains(.analyzeImage) {
            ToolWindows.showAIAnalysis(for: image)
        }

        if tasks.contains(.scanQRCode) {
            ToolWindows.showQRDecodeResult(for: image)
        }

        if tasks.contains(.doOCR) {
            // C# opens the OCR form with the capture; the window has Copy All
            await ToolWindows.showOCRResult(for: image)
        }

        if tasks.contains(.uploadImageToHost) {
            if let savedURL {
                // reuse the encoded file so bytes, name and MIME type all agree
                UploadCoordinator.uploadFile(at: savedURL, settings: settings)
            } else {
                let fileName = withNameOverride(SavePath.screenshotURL(config: config, task: settings,
                                                                       processName: processName,
                                                                       fileExtension: format.fileExtension))
                    .lastPathComponent
                UploadCoordinator.uploadImage(image, fileName: fileName,
                                              format: format, jpegQuality: settings.imageJPEGQuality,
                                              settings: settings)
            }
        }

        if tasks.contains(.sendImageToPrinter) {
            printImage(image)
        }

        // last: the upload path has already read the file's bytes by now.
        // Trash instead of C#'s permanent delete - recoverable mistakes only.
        if tasks.contains(.deleteFile), let savedURL {
            try? FileManager.default.trashItem(at: savedURL, resultingItemURL: nil)
        }

        let pending = tasks.subtracting(implemented)
        if !pending.isEmpty {
            NSLog("AfterCaptureTasks not implemented yet: %@", pending.nameString)
        }
    }

    private static func printImage(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        let view = NSImageView(frame: NSRect(origin: .zero, size: nsImage.size))
        view.image = nsImage
        view.imageScaling = .scaleProportionallyDown
        let info = NSPrintInfo.shared
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        NSApp.activate(ignoringOtherApps: true)
        NSPrintOperation(view: view, printInfo: info).run()
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
/// Drag to move, double-click to close, scroll to scale (⌘-scroll for
/// opacity), +/- keys likewise, right-click for the menu - the C#
/// PinToScreenForm interactions with its default 10% steps.
@MainActor
enum PinnedWindows {
    private static var panels: [PinPanel] = []

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

        let panel = PinPanel(image: image, size: size)
        panel.center()
        panel.orderFrontRegardless()
        panels.append(panel)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { note in
            Task { @MainActor in panels.removeAll { $0 == note.object as? PinPanel } }
        }
    }

    static func pinFromClipboard() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            Notifier.notify(title: "Pin to screen", body: "No image on the clipboard.")
            return
        }
        pin(image)
    }

    static func pinFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        pin(image)
    }

    /// C# PinToScreenFromScreen: select a region, pin the capture.
    static func pinFromScreen() {
        Task {
            guard let rect = await RegionSelectController().selectRegion() else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard let image = try? await ScreenCapture.captureRegion(cocoaRect: rect) else { return }
            pin(image)
        }
    }

    static func closeAll() {
        panels.forEach { $0.close() }
        panels.removeAll()
    }
}

final class PinPanel: NSPanel {
    private let image: NSImage
    private let baseSize: NSSize
    private var scale: CGFloat = 1

    // C# PinToScreenOptions defaults: ScaleStep/OpacityStep 10 %
    private static let step: CGFloat = 0.1

    init(image: NSImage, size: NSSize) {
        self.image = image
        self.baseSize = size
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces]

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(NSPanel.close))
        doubleClick.numberOfClicksRequired = 2
        imageView.addGestureRecognizer(doubleClick)
        contentView = imageView
    }

    override var canBecomeKey: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        let direction: CGFloat = event.scrollingDeltaY > 0 ? 1 : event.scrollingDeltaY < 0 ? -1 : 0
        guard direction != 0 else { return }
        if event.modifierFlags.contains(.command) {
            adjustOpacity(direction * Self.step)
        } else {
            adjustScale(direction * Self.step)
        }
    }

    override func keyDown(with event: NSEvent) {
        let opacity = event.modifierFlags.contains(.command)
        switch event.charactersIgnoringModifiers {
        case "+", "=": opacity ? adjustOpacity(Self.step) : adjustScale(Self.step)
        case "-", "_": opacity ? adjustOpacity(-Self.step) : adjustScale(-Self.step)
        case "w" where opacity, "\u{1B}": close()  // ⌘W / Esc
        default: super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Image", action: #selector(copyImage), keyEquivalent: "")
        menu.addItem(withTitle: "Save As…", action: #selector(saveImage), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close", action: #selector(close), keyEquivalent: "")
        menu.addItem(withTitle: "Close All Pins", action: #selector(closeAllPins), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: contentView ?? NSView())
    }

    @objc private func copyImage() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    @objc private func saveImage() {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "pinned.png"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }

    @objc private func closeAllPins() {
        MainActor.assumeIsolated { PinnedWindows.closeAll() }
    }

    /// Resizes around the window center (C# KeepCenterLocation default).
    private func adjustScale(_ delta: CGFloat) {
        scale = min(5, max(0.2, scale + delta))
        let size = NSSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let center = NSPoint(x: frame.midX, y: frame.midY)
        setFrame(NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                        width: size.width, height: size.height),
                 display: true, animate: false)
    }

    private func adjustOpacity(_ delta: CGFloat) {
        alphaValue = min(1, max(0.1, alphaValue + delta))
    }
}
