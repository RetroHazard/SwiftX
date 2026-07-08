// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import SwiftUI
import ApplicationServices
import HistoryKit
import SharedKit
import UploadKit

struct MainWindowView: View {
    @State private var items: [HistoryItem] = []
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search history", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(search.isEmpty ? "Captures will appear here" : "No matches")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HistoryRow(item: item)
                        .contextMenu { contextMenu(for: item) }
                }
                .listStyle(.inset)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: search) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.changedNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        items = HistoryStore.shared.recent(limit: 200, search: search)
    }

    @ViewBuilder
    private func contextMenu(for item: HistoryItem) -> some View {
        if !item.url.isEmpty {
            Button("Copy URL") { copyString(item.url) }
            Button("Open URL") {
                if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
            }
        }
        if FileManager.default.fileExists(atPath: item.filePath) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.filePath)])
            }
            Button("Copy File Path") { copyString(item.filePath) }
        }
    }

    private func copyString(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail = ThumbnailLoader.thumbnail(for: item.filePath) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .lineLimit(1)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.url.isEmpty {
                    Text(item.url)
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if !item.host.isEmpty, item.host != "File" {
                Text(item.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Downsampled thumbnails via ImageIO with a small cache - avoids decoding
/// full-size screenshots for every list row.
enum ThumbnailLoader {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for path: String, maxPixel: CGFloat = 128) -> NSImage? {
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard FileManager.default.fileExists(atPath: path),
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct SettingsView: View {
    @State private var config = ApplicationConfig.load()
    @State private var task = TaskSettings.load()

    private static let afterCaptureToggles: [(AfterCaptureTasks, String)] = [
        (.copyImageToClipboard, "Copy image to clipboard"),
        (.saveImageToFile, "Save image to file"),
        (.saveImageToFileWithDialog, "Save image with dialog"),
        (.pinToScreen, "Pin to screen"),
        (.copyFilePathToClipboard, "Copy file path to clipboard"),
        (.showInExplorer, "Show in Finder"),
        (.uploadImageToHost, "Upload image to host")
    ]

    private func destinationBinding() -> Binding<String> {
        Binding(
            get: { task.imageDestination },
            set: { value in
                task.imageDestination = value
                try? task.save()
            }
        )
    }

    private func s3Binding(_ keyPath: WritableKeyPath<AmazonS3Settings, String>) -> Binding<String> {
        Binding(
            get: { UploadersConfig.load().amazonS3[keyPath: keyPath] },
            set: { value in
                var config = UploadersConfig.load()
                config.amazonS3[keyPath: keyPath] = value
                try? config.save()
            }
        )
    }

    private func afterUploadBinding(_ flag: AfterUploadTasks) -> Binding<Bool> {
        Binding(
            get: { task.afterUploadJob.contains(flag) },
            set: { enabled in
                if enabled {
                    task.afterUploadJob.insert(flag)
                } else {
                    task.afterUploadJob.remove(flag)
                }
                try? task.save()
            }
        )
    }

    private func uploaderBinding() -> Binding<String> {
        Binding(
            get: { UploadersConfig.load().activeCustomUploader },
            set: { name in
                var config = UploadersConfig.load()
                config.activeCustomUploader = name
                try? config.save()
            }
        )
    }

    private func afterCaptureBinding(_ flag: AfterCaptureTasks) -> Binding<Bool> {
        Binding(
            get: { task.afterCaptureJob.contains(flag) },
            set: { enabled in
                if enabled {
                    task.afterCaptureJob.insert(flag)
                } else {
                    task.afterCaptureJob.remove(flag)
                }
                try? task.save()
            }
        )
    }

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionsView()
            }
            Section("After capture") {
                ForEach(Self.afterCaptureToggles, id: \.1) { flag, label in
                    Toggle(label, isOn: afterCaptureBinding(flag))
                }
            }
            Section("Upload destination") {
                Picker("Destination", selection: destinationBinding()) {
                    Text("Custom uploader").tag("CustomImageUploader")
                    Text("Amazon S3").tag("AmazonS3")
                }

                if task.imageDestination == "CustomImageUploader" {
                    let uploaders = CustomUploaderStore.list()
                    if uploaders.isEmpty {
                        Text("No custom uploaders imported. Use “Import Custom Uploader…” in the ShareX menu — any community .sxcu file works.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Custom uploader", selection: uploaderBinding()) {
                            ForEach(uploaders, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                } else if task.imageDestination == "AmazonS3" {
                    TextField("Access key ID", text: s3Binding(\.accessKeyID))
                    SecureField("Secret access key", text: s3Binding(\.secretAccessKey))
                    TextField("Region", text: s3Binding(\.region))
                    TextField("Bucket", text: s3Binding(\.bucket))
                    TextField("Object prefix", text: s3Binding(\.objectPrefix))
                    TextField("Custom endpoint (optional, for S3-compatible hosts)", text: s3Binding(\.endpoint))
                }

                Toggle("Shorten URL after upload (is.gd)", isOn: afterUploadBinding(.useURLShortener))
            }
            Section("Hotkeys") {
                ForEach(HotkeySettings.load().hotkeys, id: \.taskType) { hotkey in
                    LabeledContent(hotkey.taskType) {
                        Text(hotkey.combo?.displayString ?? "—")
                            .font(.body.monospaced())
                    }
                }
                Text("Edit \(HotkeySettings.fileURL.path) and relaunch to change. Recorder UI is planned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Paths") {
                LabeledContent("Screenshots folder") {
                    HStack {
                        Text(config.screenshotsFolder.path)
                            .truncationMode(.middle)
                            .lineLimit(1)
                        Button("Choose…") { chooseFolder() }
                        if config.useCustomScreenshotsPath {
                            Button("Reset") {
                                config.useCustomScreenshotsPath = false
                                config.customScreenshotsPath = ""
                                try? config.save()
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 380)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = config.screenshotsFolder
        if panel.runModal() == .OK, let url = panel.url {
            config.useCustomScreenshotsPath = true
            config.customScreenshotsPath = url.path
            try? config.save()
        }
    }
}

struct PermissionsView: View {
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var accessibility = AXIsProcessTrusted()
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        permissionRow(
            name: "Screen Recording",
            detail: "Required for all capture and recording features.",
            granted: screenRecording,
            request: { CGRequestScreenCaptureAccess() },
            settingsAnchor: "Privacy_ScreenCapture"
        )
        permissionRow(
            name: "Accessibility",
            detail: "Required for window snapping, scrolling capture and window tools.",
            granted: accessibility,
            request: {
                let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                AXIsProcessTrustedWithOptions(options)
            },
            settingsAnchor: "Privacy_Accessibility"
        )
        .onReceive(refresh) { _ in
            screenRecording = CGPreflightScreenCaptureAccess()
            accessibility = AXIsProcessTrusted()
        }
    }

    @ViewBuilder
    private func permissionRow(name: String, detail: String, granted: Bool, request: @escaping () -> Void, settingsAnchor: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Label(name, systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Request") { request() }
                Button("Open System Settings") {
                    let url = "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)"
                    NSWorkspace.shared.open(URL(string: url)!)
                }
            }
        }
    }
}
