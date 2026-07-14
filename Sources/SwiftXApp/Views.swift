// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import SwiftUI
import ApplicationServices
import CaptureKit
import HistoryKit
import SharedKit
import UniformTypeIdentifiers
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
                Menu {
                    Button("Import History…") { importHistory() }
                    Button("Statistics…") { showStats() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                // nil target: walks the responder chain to the app delegate
                Button {
                    NSApp.sendAction(#selector(AppDelegate.showSettingsWindow), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }
            .padding(8)

            UploadTaskRows()

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

    /// C# History.json/xml migration (HistoryManagerJSON/XML loaders).
    private func importHistory() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .xml]
        panel.message = "Choose a Windows ShareX History.json or History.xml"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = HistoryStore.shared.appendAll(try HistoryImport.items(fromFile: url))
            Notifier.notify(title: "History import", body: "Imported \(imported) items.")
        } catch {
            Notifier.notify(title: "History import failed", body: error.localizedDescription)
        }
    }

    private func showStats() {
        // ponytail: loads every row to group in memory, same as C#; stream via
        // SQL GROUP BY if million-row databases ever show up
        let all = HistoryStore.shared.recent(limit: Int(Int32.max))
        ToolWindows.present(title: "History Stats", resizable: true,
                            content: HistoryStatsView(text: HistoryStats.report(all)))
    }
}

/// C# shows stats in an OutputBox: monospaced text plus a copy button.
private struct HistoryStatsView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(text)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        }
        .padding(12)
        .frame(minWidth: 340, minHeight: 420)
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

    private var windowTitle: String { item.tags["WindowTitle"] ?? "" }

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
                Text(windowTitle.isEmpty
                     ? item.date.formatted(date: .abbreviated, time: .shortened)
                     : "\(item.date.formatted(date: .abbreviated, time: .shortened)) · \(windowTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
    case actions = "Actions"
    case watchFolders = "Watch Folders"
    case destinations = "Destinations"
    case customUploader = "Custom Uploader"
    case hotkeys = "Hotkeys"
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .capture: "camera.viewfinder"
        case .recording: "record.circle"
        case .actions: "terminal"
        case .watchFolders: "folder.badge.gearshape"
        case .destinations: "square.and.arrow.up"
        case .customUploader: "wrench.and.screwdriver"
        case .hotkeys: "keyboard"
        case .about: "info.circle"
        }
    }
}

/// Shared so the "About SwiftX" menu item can jump the (cached) Settings
/// window straight to the About pane, not just on first open.
@MainActor final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()
    @Published var pane: SettingsPane? = .general
}

/// About pane. Carries the GPL v3 "Appropriate Legal Notices": both copyright
/// notices, the redistribution statement, the no-warranty statement, and a
/// link to the bundled license text. Replaces the old AppKit About panel.
struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var licenseURL: URL {
        Bundle.main.url(forResource: "LICENSE", withExtension: "txt")
            ?? URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!
    }

    var body: some View {
        Section {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SwiftX").font(.title).bold()
                    Text("Version \(version)").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Link("Project page", destination: URL(string: "https://github.com/RetroHazard/SwiftX")!)
                        Link("Report an issue", destination: URL(string: "https://github.com/RetroHazard/SwiftX/issues")!)
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        Section("Credits") {
            LabeledContent("macOS port") {
                Link("RetroHazard", destination: URL(string: "https://github.com/RetroHazard")!)
            }
            LabeledContent("Based on") {
                HStack(spacing: 4) {
                    Link("ShareX", destination: URL(string: "https://github.com/ShareX/ShareX")!)
                    Text("© 2007–2026 ShareX Team").foregroundStyle(.secondary)
                }
            }
        }
        Section("License") {
            Text("macOS port © 2026 RetroHazard.\nBased on ShareX © 2007–2026 ShareX Team.")
                .font(.callout)
            Text("SwiftX is free software: you may redistribute it and/or modify it under the terms of the GNU General Public License v3. It comes with ABSOLUTELY NO WARRANTY.")
                .font(.callout)
                .foregroundStyle(.secondary)
            // SwiftUI Link won't open file:// URLs; NSWorkspace opens the
            // bundled LICENSE.txt (or the gnu.org fallback) reliably
            Button("View the full license") {
                NSWorkspace.shared.open(licenseURL)
            }
        }
    }
}

struct SettingsView: View {
    @State private var config = ApplicationConfig.load()
    @State private var task = TaskSettings.load()
    @ObservedObject private var nav = SettingsNavigator.shared

    private static let afterCaptureToggles: [(AfterCaptureTasks, String)] = [
        (.annotateImage, "Annotate image (editor)"),
        (.copyImageToClipboard, "Copy image to clipboard"),
        (.pinToScreen, "Pin to screen"),
        (.sendImageToPrinter, "Send image to printer"),
        (.saveImageToFile, "Save image to file"),
        (.saveImageToFileWithDialog, "Save image with dialog"),
        (.saveThumbnailImageToFile, "Save thumbnail image to file"),
        (.performActions, "Perform actions (external programs)"),
        (.copyFileToClipboard, "Copy file to clipboard"),
        (.copyFilePathToClipboard, "Copy file path to clipboard"),
        (.copyFolderPathToClipboard, "Copy folder path to clipboard"),
        (.showInExplorer, "Show in Finder"),
        (.uploadImageToHost, "Upload image to host"),
        (.deleteFile, "Delete file locally (moves to Trash)")
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
        uploadersBinding((\UploadersConfig.amazonS3).appending(path: keyPath))
    }

    private func uploadersBinding<T>(_ keyPath: WritableKeyPath<UploadersConfig, T>) -> Binding<T> {
        Binding(
            get: { UploadersConfig.load()[keyPath: keyPath] },
            set: { value in
                var config = UploadersConfig.load()
                config[keyPath: keyPath] = value
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
            List(SettingsPane.allCases, selection: $nav.pane) { pane in
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
                switch nav.pane ?? .general {
                case .general: generalPane
                case .capture: capturePane
                case .recording: recordingPane
                case .actions: ActionsSettingsView()
                case .watchFolders: WatchFoldersSettingsView()
                case .destinations: destinationsPane
                case .customUploader: CustomUploaderEditorView()
                case .hotkeys: HotkeysSettingsView()
                case .about: AboutView()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((nav.pane ?? .general).rawValue)
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var generalPane: some View {
        Section("Permissions") {
            PermissionsView()
        }
        Section("Notifications") {
            Toggle("Play sound after capture", isOn: taskBinding(\.playSoundAfterCapture))
            Toggle("Play sound after upload", isOn: taskBinding(\.playSoundAfterUpload))
            Text("Clicking a capture banner reveals the file; an upload banner opens the URL.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Browser extension") {
            NativeMessagingSection()
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
        Section("Image format") {
            Picker("Format", selection: taskBinding(\.imageFormat)) {
                ForEach(ImageFileFormat.allCases, id: \.rawValue) { format in
                    Text(format.rawValue).tag(format.rawValue)
                }
            }
            if task.imageFormat == "JPEG" {
                TextField("JPEG quality (1–100)",
                          value: clampedBinding(\.imageJPEGQuality, 1...100), format: .number)
            }
            Toggle("Use JPEG for large captures", isOn: taskBinding(\.imageAutoUseJPEG))
            if task.imageAutoUseJPEG {
                TextField("JPEG when width or height exceeds (px)",
                          value: clampedBinding(\.imageAutoUseJPEGSize, 64...16384), format: .number)
            }
        }
        Section("Thumbnail") {
            TextField("Thumbnail width (0 = derive from height)",
                      value: clampedBinding(\.thumbnailWidth, 0...4096), format: .number)
            TextField("Thumbnail height (0 = derive from width)",
                      value: clampedBinding(\.thumbnailHeight, 0...4096), format: .number)
            Toggle("Only if image is larger than the thumbnail", isOn: taskBinding(\.thumbnailCheckSize))
            Text("Saved next to the screenshot as “name\(task.thumbnailName)” when “Save thumbnail image to file” is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recordingPane: some View {
        Section("Video") {
            Picker("Video codec", selection: taskBinding(\.screenRecordCodec)) {
                Text("H.264 (most compatible)").tag("H264")
                Text("HEVC (smaller files)").tag("HEVC")
                Text("WebM / VP9 (requires ffmpeg)").tag("VP9")
                Text("WebM / VP8 (requires ffmpeg)").tag("VP8")
                Text("WebP animation (requires ffmpeg)").tag("WEBP")
                Text("APNG animation (requires ffmpeg)").tag("APNG")
            }
            TextField("Video frame rate (1–60 fps)",
                      value: clampedBinding(\.screenRecordFPS, 1...60), format: .number)
            TextField("GIF frame rate (1–30 fps)",
                      value: clampedBinding(\.gifFPS, 1...30), format: .number)
        }
        Section("Audio") {
            Toggle("Record system audio", isOn: taskBinding(\.screenRecordSystemAudio))
            Toggle("Record microphone", isOn: taskBinding(\.screenRecordMicrophone))
            Text("Audio applies to video recordings only; GIFs are always silent. "
                 + "Microphone capture needs macOS 15 and Microphone permission (asked on first use).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("External tools") {
            FFmpegStatusView()
            TextField("Custom ffmpeg arguments", text: taskBinding(\.screenRecordCustomFFmpegArgs))
                .font(.body.monospaced())
            Text("Applied to transcoded formats (VP9/VP8/WebP/APNG) instead of the built-in preset. "
                 + "Example: -c:v libvpx-vp9 -crf 24 -b:v 0")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var destinationsPane: some View {
        Section("Upload destination") {
            Picker("Destination", selection: destinationBinding()) {
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
            Toggle("Retry once when an upload fails", isOn: Binding(
                get: { config.retryUpload },
                set: { config.retryUpload = $0; try? config.save() }
            ))
            simpleHostFields
            cloudHostFields

            if task.imageDestination == "CustomImageUploader" {
                let uploaders = CustomUploaderStore.list()
                if uploaders.isEmpty {
                    Text("No custom uploaders imported. Use Import… in Settings → Custom Uploader — any community .sxcu file works.")
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
            Toggle("Copy URL to clipboard", isOn: afterUploadBinding(.copyURLToClipboard))
            Toggle("Open URL in browser", isOn: afterUploadBinding(.openURL))
            Toggle("Shorten URL after upload", isOn: afterUploadBinding(.useURLShortener))
            Picker("URL shortener", selection: taskBinding(\.urlShortenerDestination)) {
                ForEach(URLShortenerType.allCases, id: \.rawValue) { type in
                    Text(type.displayName).tag(type.rawValue)
                }
            }
            shortenerFields

            Toggle("Share URL after upload (opens browser)", isOn: afterUploadBinding(.shareURL))
            Picker("Sharing service", selection: taskBinding(\.urlSharingServiceDestination)) {
                ForEach(URLSharingService.allCases, id: \.rawValue) { service in
                    Text(service.displayName).tag(service.rawValue)
                }
            }
        }
    }

    /// Credential fields for the cloud storage and token-auth destinations.
    @ViewBuilder
    private var cloudHostFields: some View {
        switch task.imageDestination {
        case "BackblazeB2":
            TextField("B2 application key ID", text: uploadersBinding(\.b2ApplicationKeyId))
            SecureField("B2 application key", text: uploadersBinding(\.b2ApplicationKey))
            TextField("B2 bucket", text: uploadersBinding(\.b2BucketName))
            TextField("Upload path (name patterns allowed)", text: uploadersBinding(\.b2UploadPath))
            Toggle("Use custom URL", isOn: uploadersBinding(\.b2UseCustomUrl))
            TextField("Custom URL (e.g. https://cdn.example.com)", text: uploadersBinding(\.b2CustomUrl))
        case "AzureStorage":
            TextField("Azure account name", text: uploadersBinding(\.azureStorageAccountName))
            SecureField("Azure access key", text: uploadersBinding(\.azureStorageAccountAccessKey))
            TextField("Container", text: uploadersBinding(\.azureStorageContainer))
            TextField("Environment", text: uploadersBinding(\.azureStorageEnvironment))
            TextField("Custom domain (optional)", text: uploadersBinding(\.azureStorageCustomDomain))
            TextField("Upload path (name patterns allowed)", text: uploadersBinding(\.azureStorageUploadPath))
        case "OwnCloud":
            TextField("Server URL (https://cloud.example.com)", text: uploadersBinding(\.ownCloudHost))
            TextField("Username", text: uploadersBinding(\.ownCloudUsername))
            SecureField("Password (use an app password)", text: uploadersBinding(\.ownCloudPassword))
            TextField("Remote folder", text: uploadersBinding(\.ownCloudPath))
        case "Seafile":
            TextField("Seafile API URL (https://seafile.example.com/api2)", text: uploadersBinding(\.seafileAPIURL))
            SecureField("Auth token", text: uploadersBinding(\.seafileAuthToken))
            TextField("Library (repo) ID", text: uploadersBinding(\.seafileRepoID))
            TextField("Remote folder", text: uploadersBinding(\.seafilePath))
        case "Pushbullet":
            SecureField("Pushbullet access token", text: uploadersBinding(\.pushbulletAPIKey))
            Text("Pushes the file to all devices on the account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    /// Credential fields for the selected simple file host; keyless hosts need none.
    @ViewBuilder
    private var simpleHostFields: some View {
        switch SimpleHostDestination(rawValue: task.imageDestination) {
        case .pomf:
            TextField("Pomf upload URL (https://yourhost/upload.php)", text: uploadersBinding(\.pomf.uploadURL))
            TextField("Pomf result URL (prepended to relative file names)", text: uploadersBinding(\.pomf.resultURL))
        case .vgyme:
            SecureField("vgy.me user key (optional, links uploads to your account)", text: uploadersBinding(\.vgymeUserKey))
        case .sul:
            SecureField("s-ul API key", text: uploadersBinding(\.sulAPIKey))
        case .lobfile:
            SecureField("LobFile API key", text: uploadersBinding(\.lithiio.userAPIKey))
        case .puush:
            SecureField("Puush API key (puush.me → Account → Settings)", text: uploadersBinding(\.puushAPIKey))
        case .chevereto:
            TextField("Chevereto upload URL (https://yoursite/api/1/upload)", text: uploadersBinding(\.chevereto.uploadURL))
            SecureField("Chevereto API key", text: uploadersBinding(\.chevereto.apiKey))
            Toggle("Use direct image URL", isOn: uploadersBinding(\.cheveretoDirectURL))
        case .streamable:
            TextField("Streamable email", text: uploadersBinding(\.streamableUsername))
            SecureField("Streamable password", text: uploadersBinding(\.streamablePassword))
        case .uguu:
            Text("No configuration needed — files are temporary (up to 48 hours).")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    /// Credential fields for the selected shortener; keyless services need none.
    @ViewBuilder
    private var shortenerFields: some View {
        switch URLShortenerType(rawValue: task.urlShortenerDestination) {
        case .bitly:
            SecureField("bit.ly access token", text: uploadersBinding(\.bitlyAccessToken))
            TextField("bit.ly custom domain (optional)", text: uploadersBinding(\.bitlyDomain))
            Text("Generate a token at bitly.com → Settings → Developer settings → API.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .polr:
            TextField("Polr API URL (https://yoursite/api/v2/action/shorten)", text: uploadersBinding(\.polrAPIHostname))
            SecureField("Polr API key", text: uploadersBinding(\.polrAPIKey))
        case .kutt:
            TextField("Kutt host", text: uploadersBinding(\.kutt.host))
            SecureField("Kutt API key", text: uploadersBinding(\.kutt.apiKey))
        case .yourls:
            TextField("YOURLS API URL (https://yoursite/yourls-api.php)", text: uploadersBinding(\.yourlsAPIURL))
            SecureField("YOURLS signature", text: uploadersBinding(\.yourlsSignature))
        case .zws:
            TextField("ZWS API URL (empty = api.zws.im)", text: uploadersBinding(\.zeroWidthShortenerURL))
            SecureField("ZWS token (optional)", text: uploadersBinding(\.zeroWidthShortenerToken))
        default:
            EmptyView()
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
                Text(ffmpegPath ?? "Required for WebM/WebP/APNG export. Without it, those recordings fall back to H.264.")
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("swiftx-install-ffmpeg.command")
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
