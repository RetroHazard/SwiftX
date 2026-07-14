// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Upload-source hotkey verbs (C# UploadManager): file/folder pickers,
// clipboard upload, prompted text/URL upload, drag-and-drop window — plus the
// standalone image editor opener and the floating actions toolbar.

import AppKit
import EditorKit
import SharedKit
import SwiftUI
import UniformTypeIdentifiers
import UploadKit

@MainActor
enum UploadActions {
    static func filesUpload() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
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
        while let file = enumerator?.nextObject() as? URL {
            if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                UploadCoordinator.uploadFile(at: file)
            }
        }
    }

    /// C# UploadManager.ClipboardUpload. File URLs are checked before text:
    /// Finder copies put both file URLs and their names on the pasteboard.
    static func clipboardUpload() {
        let pasteboard = NSPasteboard.general
        if let files = clipboardFileURLs(), !files.isEmpty {
            files.forEach { UploadCoordinator.uploadFile(at: $0) }
        } else if let image = NSImage(pasteboard: pasteboard),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let name = NameParser(.fileName).parse(TaskSettings.load().nameFormatPattern)
            UploadCoordinator.uploadImage(cgImage, fileName: (name.isEmpty ? "clipboard" : name) + ".png")
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            // ponytail: C# can re-upload/shorten/share URL text via the
            // ClipboardUpload* toggles (all default false); plain text upload here
            UploadCoordinator.uploadText(text)
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

/// C# ActionsToolbar: a floating strip of one-click actions.
/// ponytail: fixed button set; C# lets users configure the list
@MainActor
enum ActionsToolbar {
    private static var window: NSPanel?

    static func toggle() {
        if let window {
            window.close()
            Self.window = nil
            return
        }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.titled, .closable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "SwiftX"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ActionsToolbarView())
        panel.setContentSize(panel.contentView!.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
    }
}

private struct ActionsToolbarView: View {
    private let actions: [(label: String, symbol: String, type: HotkeyType)] = [
        ("Capture region", "rectangle.dashed", .rectangleRegion),
        ("Capture active window", "macwindow", .activeWindow),
        ("Capture screen", "display", .printScreen),
        ("Record screen", "record.circle", .screenRecorder),
        ("Record GIF", "photo.stack", .screenRecorderGIF),
        ("Image editor", "pencil.and.outline", .imageEditor),
        ("Color picker", "eyedropper", .colorPicker),
        ("History", "clock", .openHistory),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(actions, id: \.type) { action in
                Button {
                    HotkeyDispatcher.execute(action.type)
                } label: {
                    Image(systemName: action.symbol)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .help(action.label)
            }
        }
        .padding(8)
    }
}
