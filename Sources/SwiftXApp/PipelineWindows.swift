// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Modal-style pipeline dialogs: the after-capture window (edit the task
// chain + file name per capture) and, later, the before-upload window.
// Presenters resolve when the user decides; closing the window cancels.

import AppKit
import SharedKit
import SwiftUI
import UploadKit

@MainActor
enum AfterCaptureWindow {
    enum Outcome {
        /// Settings with the user's edited task chains; fileName replaces the
        /// generated name (extension-less).
        case proceed(TaskSettings, fileName: String)
        case cancel
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        var onClose: (() -> Void)?
        func windowWillClose(_ notification: Notification) { onClose?() }
    }

    private static var activeDelegates: [WindowDelegate] = []

    static func present(image: CGImage, settings: TaskSettings, defaultFileName: String) async -> Outcome {
        await withCheckedContinuation { continuation in
          MainActor.assumeIsolated {
            var finished = false
            let delegate = WindowDelegate()
            activeDelegates.append(delegate)

            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "After Capture Tasks"
            window.isReleasedWhenClosed = false
            window.delegate = delegate

            func finish(_ outcome: Outcome) {
                MainActor.assumeIsolated {
                    guard !finished else { return }
                    finished = true
                    activeDelegates.removeAll { $0 === delegate }
                    if window.isVisible {
                        window.delegate = nil
                        window.close()
                    }
                    continuation.resume(returning: outcome)
                }
            }

            delegate.onClose = { finish(.cancel) }
            window.contentView = NSHostingView(rootView: AfterCaptureWindowView(
                image: image, settings: settings, fileName: defaultFileName
            ) { finish($0) })
            window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 700, height: 480))
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
          }
        }
    }
}

private struct AfterCaptureWindowView: View {
    let image: CGImage
    @State var settings: TaskSettings
    @State var fileName: String
    let onFinish: (AfterCaptureWindow.Outcome) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(decorative: image, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 380, maxHeight: 400)
                    .border(Color(nsColor: .separatorColor))

                Form {
                    TextField("File name:", text: $fileName)
                        .onSubmit { proceed() }
                    Section("After capture") {
                        TaskFlagToggles(value: $settings.afterCaptureJob,
                                        excluded: [.showQuickTaskMenu, .showAfterCaptureWindow])
                    }
                    Section("After upload") {
                        TaskFlagToggles(value: $settings.afterUploadJob)
                    }
                }
                .formStyle(.grouped)
                .frame(width: 340, height: 430)
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish(.cancel) }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") {
                    // C#: Copy short-circuits the chain to clipboard only
                    settings.afterCaptureJob = .copyImageToClipboard
                    proceed()
                }
                Button("Continue") { proceed() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func proceed() {
        onFinish(.proceed(settings, fileName: fileName))
    }
}

/// C# BeforeUploadForm: confirm or change the destination right before an
/// upload. Resolves with edited settings, or nil when cancelled.
@MainActor
enum BeforeUploadWindow {
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        var onClose: (() -> Void)?
        func windowWillClose(_ notification: Notification) { onClose?() }
    }

    private static var activeDelegates: [WindowDelegate] = []

    static func present(fileName: String, previewData: Data, settings: TaskSettings) async -> TaskSettings? {
        await withCheckedContinuation { continuation in
          MainActor.assumeIsolated {
            var finished = false
            let delegate = WindowDelegate()
            activeDelegates.append(delegate)

            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "Before Upload"
            window.isReleasedWhenClosed = false
            window.delegate = delegate

            func finish(_ result: TaskSettings?) {
                MainActor.assumeIsolated {
                    guard !finished else { return }
                    finished = true
                    activeDelegates.removeAll { $0 === delegate }
                    if window.isVisible {
                        window.delegate = nil
                        window.close()
                    }
                    continuation.resume(returning: result)
                }
            }

            delegate.onClose = { finish(nil) }
            window.contentView = NSHostingView(rootView: BeforeUploadView(
                fileName: fileName, preview: NSImage(data: previewData), settings: settings
            ) { finish($0) })
            window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 480, height: 360))
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
          }
        }
    }
}

private struct BeforeUploadView: View {
    let fileName: String
    let preview: NSImage?
    @State var settings: TaskSettings
    let onFinish: (TaskSettings?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(fileName) is about to be uploaded to \(destinationTitle). You may choose a different destination.")
                .frame(maxWidth: 440, alignment: .leading)

            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 440, maxHeight: 280)
                    .border(Color(nsColor: .separatorColor))
            }

            Picker("Destination:", selection: $settings.imageDestination) {
                Text("Custom uploader").tag("CustomImageUploader")
                Text("Amazon S3").tag("AmazonS3")
                Text("Backblaze B2").tag("BackblazeB2")
                Text("Azure Storage").tag("AzureStorage")
                Text("ownCloud / Nextcloud").tag("OwnCloud")
                Text("Seafile").tag("Seafile")
                Text("Pushbullet").tag("Pushbullet")
                ForEach(SimpleHostDestination.allCases, id: \.rawValue) { destination in
                    Text(destination.displayName).tag(destination.rawValue)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Upload") { onFinish(settings) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 470)
    }

    private var destinationTitle: String {
        SimpleHostDestination(rawValue: settings.imageDestination)?.displayName
            ?? settings.imageDestination
    }
}

// MARK: - After-upload window (C# AfterUploadForm: link formats + copy)

@MainActor
enum AfterUploadWindow {
    static func present(result: UploadResult, finalURL: String) {
        ToolWindows.present(title: "Upload complete", resizable: true,
                            content: AfterUploadLinksView(result: result, finalURL: finalURL))
    }
}

private struct AfterUploadLinksView: View {
    let result: UploadResult
    let finalURL: String

    private var formats: [(String, String)] {
        var rows: [(String, String)] = [("URL", finalURL)]
        if finalURL != result.url { rows.append(("Original URL", result.url)) }
        if !result.thumbnailURL.isEmpty { rows.append(("Thumbnail URL", result.thumbnailURL)) }
        if !result.deletionURL.isEmpty { rows.append(("Deletion URL", result.deletionURL)) }
        // C# hides the image markups for non-image URLs
        let ext = URL(string: result.url)?.pathExtension.lowercased() ?? ""
        if ["png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "webp"].contains(ext) {
            rows.append(("Forum (BBCode)", "[img]\(result.url)[/img]"))
            rows.append(("HTML", "<img src=\"\(result.url)\"/>"))
            rows.append(("Markdown", "![](\(result.url))"))
            rows.append(("Wiki", "[\(result.url)]"))
        }
        return rows
    }

    var body: some View {
        Form {
            ForEach(formats, id: \.0) { label, value in
                LabeledContent(label) {
                    HStack {
                        Text(value)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 240)
    }
}
