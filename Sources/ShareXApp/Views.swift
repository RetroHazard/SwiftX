// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import SwiftUI
import ApplicationServices
import CaptureKit
import HistoryKit
import SharedKit
import UploadKit

enum TimeRange: String, CaseIterable {
    case any = "Any time"
    case today = "Today"
    case week = "Last 7 days"
    case month = "Last 30 days"

    var startDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .any: return nil
        case .today: return calendar.startOfDay(for: Date())
        case .week: return calendar.date(byAdding: .day, value: -7, to: Date())
        case .month: return calendar.date(byAdding: .day, value: -30, to: Date())
        }
    }
}

struct MainWindowView: View {
    @State private var items: [HistoryItem] = []
    @State private var search = ""
    @State private var timeRange: TimeRange = .any
    @State private var favoritesOnly = false
    @State private var viewMode = ApplicationConfig.load().taskViewMode

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Search history", text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .fixedSize()
                Toggle(isOn: $favoritesOnly) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help("Show favorites only")
                Picker("", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag("ListView")
                    Image(systemName: "square.grid.2x2").tag("ThumbnailView")
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(8)

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(search.isEmpty && !favoritesOnly && timeRange == .any
                         ? "Captures will appear here" : "No matches")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == "ThumbnailView" {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(items) { item in
                            HistoryGridCell(item: item)
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .padding(12)
                }
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
        .onChange(of: timeRange) { reload() }
        .onChange(of: favoritesOnly) { reload() }
        .onChange(of: viewMode) {
            var config = ApplicationConfig.load()
            config.taskViewMode = viewMode
            try? config.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: HistoryStore.changedNotification)) { _ in
            reload()
        }
    }

    private func reload() {
        items = HistoryStore.shared.recent(
            limit: 200, search: search,
            favoritesOnly: favoritesOnly, from: timeRange.startDate
        )
    }

    @ViewBuilder
    private func contextMenu(for item: HistoryItem) -> some View {
        Button(item.isFavorite ? "Remove Favorite" : "Add Favorite") {
            HistoryStore.shared.setFavorite(id: item.id, !item.isFavorite)
        }
        Divider()
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

struct HistoryGridCell: View {
    let item: HistoryItem

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail = ThumbnailLoader.thumbnail(for: item.filePath, maxPixel: 320) {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 160, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .shadow(radius: 2)
                        .padding(4)
                }
            }
            Text(item.fileName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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
        let cacheKey = "\(path)#\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard FileManager.default.fileExists(atPath: path),
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: cacheKey)
        return image
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general = "General"
    case capture = "Capture"
    case recording = "Recording"
    case destinations = "Destinations"
    case hotkeys = "Hotkeys"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .recording: "record.circle"
        case .destinations: "square.and.arrow.up"
        case .hotkeys: "keyboard"
        }
    }
}

struct SettingsView: View {
    @State private var config = ApplicationConfig.load()
    @State private var task = TaskSettings.load()
    @State private var pane: SettingsPane? = .general

    private static let afterCaptureToggles: [(AfterCaptureTasks, String)] = [
        (.annotateImage, "Annotate image (editor)"),
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

    /// Text entry can produce anything; clamp to the valid range on commit.
    private func clampedBinding(_ keyPath: WritableKeyPath<TaskSettings, Int>,
                                _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { task[keyPath: keyPath] },
            set: { value in
                task[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
                try? task.save()
            }
        )
    }

    private func taskBinding<T>(_ keyPath: WritableKeyPath<TaskSettings, T>) -> Binding<T> {
        Binding(
            get: { task[keyPath: keyPath] },
            set: { value in
                task[keyPath: keyPath] = value
                try? task.save()
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
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                // explicit tag: List's implicit selection value is the String id,
                // which never matches our SettingsPane? binding
                Label(pane.rawValue, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
            // the toggle floats misaligned in a hand-made NSWindow's title bar;
            // a fixed settings sidebar doesn't need collapsing anyway
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form {
                switch pane ?? .general {
                case .general: generalPane
                case .capture: capturePane
                case .recording: recordingPane
                case .destinations: destinationsPane
                case .hotkeys: hotkeysPane
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane ?? .general).rawValue)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var generalPane: some View {
        Section("Permissions") {
            PermissionsView()
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

    @ViewBuilder
    private var capturePane: some View {
        Section("After capture") {
            ForEach(Self.afterCaptureToggles, id: \.1) { flag, label in
                Toggle(label, isOn: afterCaptureBinding(flag))
            }
        }
    }

    @ViewBuilder
    private var recordingPane: some View {
        Section("Video") {
            Picker("Video codec", selection: taskBinding(\.screenRecordCodec)) {
                Text("H.264 (most compatible)").tag("H264")
                Text("HEVC (smaller files)").tag("HEVC")
                Text("WebM / VP9 (requires ffmpeg)").tag("VP9")
            }
            TextField("Video frame rate (1–60 fps)",
                      value: clampedBinding(\.screenRecordFPS, 1...60), format: .number)
            TextField("GIF frame rate (1–30 fps)",
                      value: clampedBinding(\.gifFPS, 1...30), format: .number)
        }
        Section("External tools") {
            FFmpegStatusView()
        }
    }

    @ViewBuilder
    private var destinationsPane: some View {
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
        }
        Section("After upload") {
            Toggle("Shorten URL after upload (is.gd)", isOn: afterUploadBinding(.useURLShortener))
        }
    }

    @ViewBuilder
    private var hotkeysPane: some View {
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

/// ffmpeg availability, styled after the TCC permission rows. ffmpeg is only
/// needed for formats VideoToolbox can't encode (WebM/VP9 today).
struct FFmpegStatusView: View {
    @State private var ffmpegPath = FFmpeg.installedPath
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Label(ffmpegPath != nil ? "ffmpeg installed" : "ffmpeg not installed",
                      systemImage: ffmpegPath != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ffmpegPath != nil ? .green : .red)
                Text(ffmpegPath ?? "Required for WebM/VP9 export. Without it, VP9 recordings fall back to H.264.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if ffmpegPath == nil {
                if FFmpeg.homebrewPath != nil {
                    Button("Install via Homebrew") { installViaHomebrew() }
                } else {
                    Button("Get Homebrew") {
                        NSWorkspace.shared.open(URL(string: "https://brew.sh")!)
                    }
                }
            }
        }
        .onReceive(refresh) { _ in ffmpegPath = FFmpeg.installedPath }
    }

    /// Runs the install in Terminal via a .command file: progress stays
    /// visible and no Apple-events automation permission is needed.
    private func installViaHomebrew() {
        guard let brew = FFmpeg.homebrewPath else { return }
        let script = "#!/bin/zsh\n\(brew) install ffmpeg\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sharex-install-ffmpeg.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("Could not launch ffmpeg install: %@", error.localizedDescription)
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
