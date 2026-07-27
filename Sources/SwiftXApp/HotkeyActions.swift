// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Upload-source hotkey verbs (C# UploadManager): file/folder pickers,
// clipboard upload, prompted text/URL upload, drag-and-drop window — plus the
// standalone image editor opener and the floating actions toolbar.

import AppKit
import EditorKit
import SharedKit
import SwiftUI
import ToolsKit
import UniformTypeIdentifiers
import UploadKit

@MainActor
enum UploadActions {
    static func filesUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              UploadCoordinator.confirmMultiUpload(count: panel.urls.count) else { return }
        panel.urls.forEach { UploadCoordinator.uploadFile(at: $0) }
    }

    static func folderUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        // C# UploadFolder expands the directory into one task per file
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var files: [URL] = []
        while let file = enumerator?.nextObject() as? URL {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(file)
            }
        }
        guard UploadCoordinator.confirmMultiUpload(count: files.count) else { return }
        files.forEach { UploadCoordinator.uploadFile(at: $0) }
    }

    /// C# UploadManager.ClipboardUpload. File URLs are checked before text:
    /// Finder copies put both file URLs and their names on the pasteboard.
    /// The ClipboardUpload* toggles reroute URLs and folders before the plain
    /// text/image/file fallbacks run.
    static func clipboardUpload() {
        let settings = TaskSettings.load()
        let pasteboard = NSPasteboard.general
        defer {
            // C# AutoClearClipboard: content is already captured in memory
            if settings.autoClearClipboard { pasteboard.clearContents() }
        }
        if let files = clipboardFileURLs(), !files.isEmpty {
            if settings.clipboardUploadAutoIndexFolder, files.count == 1,
               (try? files[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                uploadFolderIndex(files[0])
                return
            }
            guard UploadCoordinator.confirmMultiUpload(count: files.count) else { return }
            files.forEach { UploadCoordinator.uploadFile(at: $0) }
        } else if let image = NSImage(pasteboard: pasteboard),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let name = NameParser.forTask(.fileName, settings: settings).parse(settings.nameFormatPattern)
            UploadCoordinator.uploadImage(cgImage, fileName: (name.isEmpty ? "clipboard" : name) + ".png")
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            uploadTextOrURL(text, settings: settings)
        }
    }

    /// Routes text that may be a bare http(s) URL, in the C# order: download
    /// its contents, else shorten it, else hand it to the sharing service —
    /// with a plain text upload as the fallback. Shared by ClipboardUpload and
    /// the Share extension, which both hand us "some text, possibly a link".
    static func uploadTextOrURL(_ text: String, settings: TaskSettings) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased()) {
            if settings.clipboardUploadURLContents {
                Task { await UploadCoordinator.downloadAndUpload(url) }
                return
            }
            if settings.clipboardUploadShortenURL {
                shortenAndCopy(trimmed)
                return
            }
            if settings.clipboardUploadShareURL {
                let service = URLSharingService(rawValue: settings.urlSharingServiceDestination) ?? .email
                if let share = service.shareURL(for: trimmed) {
                    NSWorkspace.shared.open(share)
                }
                return
            }
        }
        UploadCoordinator.uploadText(text)
    }

    /// C# ClipboardUploadAutoIndexFolder: index the copied folder and upload
    /// the HTML index instead of the folder path text.
    private static func uploadFolderIndex(_ folder: URL) {
        var options = IndexerOptions()
        options.format = .html
        guard let html = try? FolderIndexer.index(folder: folder, options: options) else {
            Notifier.notify(title: "Folder index failed", body: folder.lastPathComponent, event: .error)
            return
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-index-\(UUID().uuidString)")
            .appendingPathComponent(folder.lastPathComponent + ".html")
        try? FileManager.default.createDirectory(at: temp.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        guard (try? Data(html.utf8).write(to: temp)) != nil else { return }
        UploadCoordinator.uploadFile(at: temp)
    }

    private static func shortenAndCopy(_ urlString: String) {
        Task {
            let type = URLShortenerType(rawValue: TaskSettings.load().urlShortenerDestination) ?? .isgd
            guard let short = try? await URLShortener.shorten(urlString, type: type) else {
                Notifier.notify(title: "URL shortener", body: "Could not shorten \(urlString).",
                                event: .error)
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(short, forType: .string)
            Notifier.notify(title: "URL shortened", body: short, url: short)
        }
    }

    /// C# ClipboardUploadWithContentViewer shows an editable preview form.
    /// ponytail: a summary + confirm alert covers the confirmation intent
    static func clipboardUploadWithContentViewer() {
        let pasteboard = NSPasteboard.general
        let summary: String
        if let files = clipboardFileURLs(), !files.isEmpty {
            summary = files.map(\.lastPathComponent).joined(separator: "\n")
        } else if let image = NSImage(pasteboard: pasteboard) {
            summary = "Image \(Int(image.size.width)) × \(Int(image.size.height))"
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            summary = String(text.prefix(300))
        } else {
            Notifier.notify(title: "Clipboard upload", body: "The clipboard is empty.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Upload clipboard content?"
        alert.informativeText = summary
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clipboardUpload()
    }

    /// C# ShowTextUploadDialog.
    static func uploadTextPrompt() {
        let alert = NSAlert()
        alert.messageText = "Upload text"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let textView = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Upload")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textView
        guard alert.runModal() == .alertFirstButtonReturn, !textView.string.isEmpty else { return }
        UploadCoordinator.uploadText(textView.string)
    }

    /// C# UploadManager.UploadURL: prompt (clipboard URL prefilled) → download → upload.
    static func uploadURLPrompt() {
        guard let entered = inputBox("URL to download from and upload", prefill: clipboardURL()),
              let url = URL(string: entered) else { return }
        Task { await UploadCoordinator.downloadAndUpload(url) }
    }

    /// C# ShowShortenURLDialog; the short URL lands on the clipboard.
    static func shortenURLPrompt() {
        guard let entered = inputBox("URL to shorten", prefill: clipboardURL()) else { return }
        Task {
            let type = URLShortenerType(rawValue: TaskSettings.load().urlShortenerDestination) ?? .isgd
            guard let short = try? await URLShortener.shorten(entered, type: type) else {
                Notifier.notify(title: "URL shortener", body: "Could not shorten \(entered).")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(short, forType: .string)
            Notifier.notify(title: "URL shortened", body: short, url: short)
        }
    }

    /// C# OpenImageEditor: pick an image, annotate it, then run the normal
    /// after-capture chain on the result (annotate stripped to avoid looping).
    static func openImageEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        Task {
            guard let edited = await ImageEditorPresenter.present(image: image) else { return }
            var settings = TaskSettings.load()
            settings.afterCaptureJob.remove(.annotateImage)
            await AfterCapturePipeline.run(image: edited, settings: settings)
        }
    }

    private static func clipboardFileURLs() -> [URL]? {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL])
    }

    private static func clipboardURL() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased())
        else { return nil }
        return text
    }

    private static func inputBox(_ title: String, prefill: String?) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.stringValue = prefill ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

/// C# DropForm: a small always-on-top target; anything dropped uploads.
@MainActor
enum DropWindow {
    private static var window: NSPanel?

    static func toggle() {
        if let window {
            window.close()
            Self.window = nil
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 140),
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Drop to upload"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DropTargetView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }
}

private struct DropTargetView: View {
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.largeTitle)
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop files here")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : .clear)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL
                    else { return }
                    Task { @MainActor in UploadCoordinator.uploadFile(at: url) }
                }
            }
            return true
        }
    }
}

/// C# ActionsToolbar: a floating strip of one-click actions. The button list
/// comes from ApplicationConfig.actionsToolbarList (C# ActionsToolbarList);
/// lock position and run-at-startup follow their C# keys too.
@MainActor
enum ActionsToolbar {
    private static var window: NSPanel?

    /// Known symbols; anything else gets a generic bolt with its display name.
    static let symbols: [HotkeyType: String] = [
        .rectangleRegion: "rectangle.dashed",
        .lastRegion: "rectangle.dashed.badge.record",
        .activeWindow: "macwindow",
        .printScreen: "display",
        .activeMonitor: "display",
        .scrollingCapture: "arrow.up.and.down.text.horizontal",
        .autoCapture: "timer",
        .screenRecorder: "record.circle",
        .startScreenRecorder: "record.circle.fill",
        .screenRecorderGIF: "photo.stack",
        .stopScreenRecording: "stop.circle",
        .abortScreenRecording: "xmark.circle",
        .imageEditor: "pencil.and.outline",
        .imageEffects: "wand.and.stars",
        .imageBeautifier: "sparkles",
        .colorPicker: "eyedropper",
        .screenColorPicker: "eyedropper.halffull",
        .ruler: "ruler",
        .ocr: "text.viewfinder",
        .qrCode: "qrcode",
        .hashCheck: "number",
        .pinToScreen: "pin",
        .fileUpload: "square.and.arrow.up",
        .folderUpload: "folder.badge.plus",
        .clipboardUpload: "doc.on.clipboard",
        .uploadURL: "link.badge.plus",
        .shortenURL: "link",
        .dragDropUpload: "tray.and.arrow.down",
        .stopUploads: "stop.circle.fill",
        .openMainWindow: "macwindow.on.rectangle",
        .openHistory: "clock",
        .openScreenshotsFolder: "folder",
        .toggleTrayMenu: "filemenu.and.selection"
    ]

    static func toggle() {
        if let window {
            window.close()
            Self.window = nil
            return
        }
        show()
    }

    static func show() {
        guard window == nil else { return }
        let config = ApplicationConfig.load()
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "SwiftX"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isMovable = !config.actionsToolbarLockPosition
        panel.contentView = NSHostingView(rootView: ActionsToolbarView())
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }
}

private struct ActionsToolbarView: View {
    private let actions: [HotkeyType] = ApplicationConfig.load().actionsToolbarList
        .compactMap { HotkeyType(rawValue: $0) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions, id: \.rawValue) { type in
                Button {
                    HotkeyDispatcher.execute(type)
                } label: {
                    Image(systemName: ActionsToolbar.symbols[type] ?? "bolt")
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .help(HotkeysSettingsView.displayName(for: type))
            }
        }
        .padding(8)
    }
}
