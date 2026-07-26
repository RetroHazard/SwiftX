// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE

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
                    Button("Import Folder…") { importFolder() }
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

    /// Upstream v21 "import folder": ingest a directory of images/media into history.
    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Choose a folder of images or recordings to add to history"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported = HistoryStore.shared.appendAll(HistoryImport.items(fromFolder: url))
        Notifier.notify(title: "Folder import", body: "Imported \(imported) items.")
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
                    Text("© 2026 RetroHazard").font(.callout).foregroundStyle(.secondary)
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
            LabeledContent("Developed by") {
                Link("RetroHazard", destination: URL(string: "https://github.com/RetroHazard")!)
            }
            LabeledContent("Derived from") {
                Link("ShareX", destination: URL(string: "https://github.com/ShareX/ShareX")!)
            }
            Text("SwiftX is not affiliated with or endorsed by the ShareX Team.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("License") {
            // GPL v3 §5(d) copyright notice: SwiftX's own plus the preserved
            // upstream notice, matching the source-file header wording
            Text("© 2026 RetroHazard.\nContains code derived from ShareX, © 2007–2026 ShareX Team.")
                .font(.callout)
            Text("SwiftX is free software: you may redistribute it and/or modify it under the terms of the GNU General Public License v3. It comes with ABSOLUTELY NO WARRANTY.")
                .font(.callout)
                .foregroundStyle(.secondary)
            // SwiftUI Link won't open file:// URLs; NSWorkspace opens the
            // bundled LICENSE (or the gnu.org fallback) reliably
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

    private func destinationBinding(_ keyPath: WritableKeyPath<TaskSettings, String>) -> Binding<String> {
        Binding(
            get: { task[keyPath: keyPath] },
            set: { value in
                task[keyPath: keyPath] = value
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

    private func uploaderBinding(_ keyPath: WritableKeyPath<UploadersConfig, String>
                                    = \.activeCustomUploader) -> Binding<String> {
        Binding(
            get: { UploadersConfig.load()[keyPath: keyPath] },
            set: { name in
                var config = UploadersConfig.load()
                config[keyPath: keyPath] = name
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

    private func clampedDoubleBinding(_ keyPath: WritableKeyPath<TaskSettings, Double>,
                                      _ range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { task[keyPath: keyPath] },
            set: { value in
                task[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
                try? task.save()
            }
        )
    }

    private func configBinding<T>(_ keyPath: WritableKeyPath<ApplicationConfig, T>) -> Binding<T> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { value in
                config[keyPath: keyPath] = value
                try? config.save()
            }
        )
    }

    private func clampedConfigBinding(_ keyPath: WritableKeyPath<ApplicationConfig, Int>,
                                      _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { config[keyPath: keyPath] },
            set: { value in
                config[keyPath: keyPath] = min(max(value, range.lowerBound), range.upperBound)
                try? config.save()
            }
        )
    }

    /// Toggle + file picker pair for the C# custom notification sound slots.
    @ViewBuilder
    private func customSoundRows(_ label: String,
                                 use: WritableKeyPath<TaskSettings, Bool>,
                                 path: WritableKeyPath<TaskSettings, String>) -> some View {
        Toggle(label, isOn: taskBinding(use))
        if task[keyPath: use] {
            LabeledContent("Sound file") {
                HStack {
                    Text(task[keyPath: path].isEmpty
                         ? "None chosen"
                         : (task[keyPath: path] as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseSoundFile(path) }
                }
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "SwiftX-Backup-\(stamp.string(from: Date())).zip"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SettingsBackup.export(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Notifier.notify(title: "Settings export failed", body: error.localizedDescription,
                            event: .error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .init(filenameExtension: "sxb") ?? .zip]
        panel.message = "Choose a SwiftX settings backup or a Windows ShareX .sxb backup"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Both backup flavors are plain zips; extract once and sniff which one
        // this is (Windows nests task settings under DefaultTaskSettings).
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftx-import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try SettingsBackup.extract(url, to: staging)
        } catch {
            Notifier.notify(title: "Settings import failed", body: error.localizedDescription,
                            event: .error)
            return
        }

        if SettingsBackup.isWindowsShareXBackup(extractedAt: staging) {
            importWindowsBackup(extractedAt: staging, named: url.lastPathComponent)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Replace current settings?"
        alert.informativeText = "Settings, hotkeys and custom uploaders will be replaced with "
            + "the backup's contents. Keychain secrets are not part of backups and must be re-entered."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try SettingsBackup.restore(from: url)
            reloadAfterImport()
            Notifier.notify(title: "Settings restored", body: url.lastPathComponent)
        } catch {
            Notifier.notify(title: "Settings import failed", body: error.localizedDescription,
                            event: .error)
        }
    }

    /// Windows ShareX .sxb: maps what has a macOS equivalent onto the current
    /// settings (a merge, unlike the native replace) and offers to bring the
    /// backup's upload history along.
    private func importWindowsBackup(extractedAt staging: URL, named name: String) {
        let alert = NSAlert()
        alert.messageText = "Import Windows ShareX backup?"
        alert.informativeText = "Settings, hotkeys and custom uploaders from \(name) will be "
            + "merged into your current configuration. Values with no macOS equivalent "
            + "(Windows paths, OAuth accounts, Windows-only hotkeys) are skipped. "
            + "Upload history can be imported too — repeating the import later would duplicate it."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Import Without History")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response != .alertThirdButtonReturn else { return }

        do {
            let summary = try ShareXBackupImport.apply(extractedAt: staging)
            var importedHistory = 0
            if response == .alertFirstButtonReturn, let database = summary.historyDatabase {
                importedHistory = HistoryStore.shared.appendAll(
                    HistoryImport.items(fromSQLiteDatabase: database))
            }
            reloadAfterImport()

            var parts = ["Settings imported."]
            if !summary.importedUploaders.isEmpty {
                parts.append("\(summary.importedUploaders.count) custom uploader(s).")
            }
            if summary.importedHotkeys > 0 || summary.skippedHotkeys > 0 {
                parts.append("\(summary.importedHotkeys) hotkey(s)"
                    + (summary.skippedHotkeys > 0
                       ? ", \(summary.skippedHotkeys) without a macOS key skipped." : "."))
            }
            if importedHistory > 0 {
                parts.append("\(importedHistory) history entries.")
            }
            Notifier.notify(title: "ShareX backup imported", body: parts.joined(separator: " "))
        } catch {
            Notifier.notify(title: "ShareX import failed", body: error.localizedDescription,
                            event: .error)
        }
    }

    private func reloadAfterImport() {
        config = ApplicationConfig.load()
        task = TaskSettings.load()
        HotkeyRegistrar.applyAll()
        WatchFolderCenter.shared.applySettings()
    }

    /// Visibility toggle for one status-bar menu entry (stored inverted:
    /// the config keeps the hidden list so new items default to visible).
    private func trayItemVisibleBinding(_ id: TrayMenuItemID) -> Binding<Bool> {
        Binding(
            get: { !config.trayMenuHiddenItems.contains(id.rawValue) },
            set: { visible in
                if visible {
                    config.trayMenuHiddenItems.removeAll { $0 == id.rawValue }
                } else if !config.trayMenuHiddenItems.contains(id.rawValue) {
                    config.trayMenuHiddenItems.append(id.rawValue)
                }
                try? config.save()
            }
        )
    }

    private func moveToolbarItem(_ index: Int, by delta: Int) {
        let target = index + delta
        guard config.actionsToolbarList.indices.contains(index),
              config.actionsToolbarList.indices.contains(target) else { return }
        config.actionsToolbarList.swapAt(index, target)
        try? config.save()
    }

    private func chooseSoundFile(_ keyPath: WritableKeyPath<TaskSettings, String>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        task[keyPath: keyPath] = url.path
        try? task.save()
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
            Toggle("Show notification banners", isOn: taskBinding(\.showToastNotificationAfterTaskCompleted))
            Toggle("Suppress while a fullscreen app is active",
                   isOn: taskBinding(\.disableNotificationsOnFullscreen))
            Toggle("Play sound after capture", isOn: taskBinding(\.playSoundAfterCapture))
            customSoundRows("Custom capture sound",
                            use: \.useCustomCaptureSound, path: \.customCaptureSoundPath)
            Toggle("Play sound after upload", isOn: taskBinding(\.playSoundAfterUpload))
            customSoundRows("Custom completion sound",
                            use: \.useCustomTaskCompletedSound, path: \.customTaskCompletedSoundPath)
            customSoundRows("Custom error sound",
                            use: \.useCustomErrorSound, path: \.customErrorSoundPath)
            Text("Upload banners offer Copy URL / Open buttons; file banners offer "
                 + "Show in Finder / Annotate / Delete. Clicking the banner itself opens the "
                 + "URL or reveals the file.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Menu bar") {
            Picker("Left click", selection: configBinding(\.trayLeftClickAction)) {
                Text("Open the menu").tag("ToggleTrayMenu")
                Text("Open main window").tag("OpenMainWindow")
                Text("Capture region").tag("RectangleRegion")
                Text("Capture full screen").tag("PrintScreen")
                Text("Capture active window").tag("ActiveWindow")
                Text("Upload from clipboard").tag("ClipboardUpload")
                Text("Upload file…").tag("FileUpload")
                Text("Image editor").tag("ImageEditor")
                Text("Open screenshots folder").tag("OpenScreenshotsFolder")
            }
            Text("Right click always opens the menu.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show upload progress in the icon", isOn: configBinding(\.trayIconProgressEnabled))
            Toggle("Show Recent submenu", isOn: configBinding(\.recentTasksShowInTrayMenu))
            if config.recentTasksShowInTrayMenu {
                TextField("Recent entries shown (1–30)",
                          value: clampedConfigBinding(\.recentTasksMaxCount, 1...30), format: .number)
            }
            DisclosureGroup("Menu items") {
                ForEach(TrayMenuItemID.allCases, id: \.rawValue) { id in
                    Toggle(id.displayName, isOn: trayItemVisibleBinding(id))
                }
                Text("Unchecked items are hidden from the menu bar menu. Settings and Quit "
                     + "always stay, and a running recording keeps its stop controls visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Hotkey guards") {
            Toggle("Disable hotkeys while a fullscreen app is active",
                   isOn: configBinding(\.disableHotkeysOnFullscreen))
            TextField("Ignore hotkey repeats within (ms, 0 = off)",
                      value: clampedConfigBinding(\.hotkeyRepeatLimit, 0...5000), format: .number)
        }
        Section("Actions toolbar") {
            ForEach(config.actionsToolbarList.indices, id: \.self) { index in
                let type = HotkeyType(rawValue: config.actionsToolbarList[index])
                HStack {
                    Image(systemName: type.flatMap { ActionsToolbar.symbols[$0] } ?? "bolt")
                        .frame(width: 20)
                    Text(type.map { HotkeysSettingsView.displayName(for: $0) }
                         ?? config.actionsToolbarList[index])
                    Spacer()
                    Button { moveToolbarItem(index, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                    Button { moveToolbarItem(index, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(index == config.actionsToolbarList.count - 1)
                    Button {
                        config.actionsToolbarList.remove(at: index)
                        try? config.save()
                    } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                }
            }
            Menu("Add Button") {
                ForEach(ActionsToolbar.symbols.keys.sorted { $0.rawValue < $1.rawValue },
                        id: \.rawValue) { type in
                    Button {
                        config.actionsToolbarList.append(type.rawValue)
                        try? config.save()
                    } label: {
                        Label(HotkeysSettingsView.displayName(for: type),
                              systemImage: ActionsToolbar.symbols[type] ?? "bolt")
                    }
                }
            }
            Toggle("Lock toolbar position", isOn: configBinding(\.actionsToolbarLockPosition))
            Toggle("Open toolbar at launch", isOn: configBinding(\.actionsToolbarRunAtStartup))
            Text("Reopen the toolbar to apply button and lock changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Browser extension") {
            NativeMessagingSection()
        }
        Section("Backup") {
            HStack {
                Button("Export Settings…") { exportSettings() }
                Button("Import Settings…") { importSettings() }
            }
            Text("Backups contain settings, hotkeys, effects presets and custom uploaders. "
                 + "API keys and OAuth tokens live in the Keychain and are never exported — "
                 + "re-enter or reconnect them after restoring on another Mac. History is "
                 + "not included; use the main window's import tools for it. Import also "
                 + "accepts Windows ShareX .sxb backups, including their upload history.")
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

    @ViewBuilder
    private var capturePane: some View {
        Section("Capture") {
            TextField("Screenshot delay (seconds, 0 = off)",
                      value: clampedDoubleBinding(\.screenshotDelay, 0...60), format: .number)
            Toggle("Show cursor in screenshots", isOn: taskBinding(\.showCursor))
        }
        Section("After capture") {
            ForEach(Self.afterCaptureToggles, id: \.1) { flag, label in
                Toggle(label, isOn: afterCaptureBinding(flag))
            }
        }
        Section("Image effects pipeline") {
            Toggle("Open the effects window after capture", isOn: taskBinding(\.showImageEffectsWindowAfterCapture))
            Toggle("Apply effects to region captures only", isOn: taskBinding(\.imageEffectOnlyRegionCapture))
            Toggle("Use a random preset each capture", isOn: taskBinding(\.useRandomImageEffect))
            Text("Applies when the “Add image effects” task runs (quick tasks, after-capture window). "
                 + "Presets are managed in Tools → Image Effects.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if task.imageFormat == "PNG" {
                Picker("PNG bit depth", selection: taskBinding(\.imagePNGBitDepth)) {
                    Text("Automatic").tag("Default")
                    Text("32-bit (keeps transparency)").tag("Bit32")
                    Text("24-bit (flattens transparency)").tag("Bit24")
                }
            }
            if task.imageFormat == "GIF" {
                Picker("GIF palette", selection: taskBinding(\.imageGIFQuality)) {
                    Text("Automatic").tag("Default")
                    Text("256 colors").tag("Bit8")
                    Text("16 colors (encodes as 256 on macOS)").tag("Bit4")
                    Text("Grayscale").tag("Grayscale")
                }
            }
            Toggle("Use JPEG for large captures", isOn: taskBinding(\.imageAutoUseJPEG))
            if task.imageAutoUseJPEG {
                TextField("JPEG when width or height exceeds (px)",
                          value: clampedBinding(\.imageAutoUseJPEGSize, 64...16384), format: .number)
                TextField("Auto-JPEG quality (1–100)",
                          value: clampedBinding(\.imageAutoJPEGQuality, 1...100), format: .number)
            }
            Picker("When the file name exists", selection: taskBinding(\.fileExistAction)) {
                Text("Add a number (name_1)").tag("UniqueName")
                Text("Ask").tag("Ask")
                Text("Overwrite").tag("Overwrite")
                Text("Skip saving").tag("Cancel")
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
            Toggle("Two-pass encoding (VP9/VP8, needs ffmpeg)",
                   isOn: taskBinding(\.screenRecordTwoPassEncoding))
        }
        Section("Session") {
            TextField("Start countdown (seconds, 0 = immediate)",
                      value: clampedDoubleBinding(\.screenRecordStartDelay, 0...60), format: .number)
            Toggle("Fixed duration", isOn: taskBinding(\.screenRecordFixedDuration))
            if task.screenRecordFixedDuration {
                TextField("Stop after (seconds)",
                          value: clampedDoubleBinding(\.screenRecordDuration, 1...86400), format: .number)
            }
            Toggle("Confirm before aborting a recording",
                   isOn: taskBinding(\.screenRecordAskConfirmationOnAbort))
            Toggle("Show cursor in recordings", isOn: taskBinding(\.screenRecordShowCursor))
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

    /// The three per-type "custom uploader" sentinels (C# enum member names).
    private static let customUploaderTags: Set<String> = [
        "CustomImageUploader", "CustomTextUploader", "CustomFileUploader"
    ]

    /// Distinct destinations selected across the three pickers, so each host's
    /// credential fields render once even when types share a destination.
    private var configurableDestinations: [String] {
        var seen = Set<String>()
        return [task.imageDestination, task.textDestination, task.fileDestination].filter { destination in
            guard !Self.customUploaderTags.contains(destination) else { return false }
            return seen.insert(destination).inserted
        }
    }

    private func destinationDisplayName(_ destination: String) -> String {
        switch destination {
        case "AmazonS3": return "Amazon S3"
        case "BackblazeB2": return "Backblaze B2"
        case "AzureStorage": return "Azure Storage"
        case "OwnCloud": return "ownCloud / Nextcloud"
        case "Seafile": return "Seafile"
        case "Pushbullet": return "Pushbullet"
        default:
            return SimpleHostDestination(rawValue: destination)?.displayName
                ?? OAuthProviderID(rawValue: destination)?.displayName
                ?? destination
        }
    }

    @ViewBuilder
    private func destinationPicker(_ label: String, customTag: String,
                                   selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text("Custom uploader").tag(customTag)
            Text("Amazon S3").tag("AmazonS3")
            Text("Backblaze B2").tag("BackblazeB2")
            Text("Azure Storage").tag("AzureStorage")
            Text("ownCloud / Nextcloud").tag("OwnCloud")
            Text("Seafile").tag("Seafile")
            Text("Pushbullet").tag("Pushbullet")
            ForEach(SimpleHostDestination.allCases, id: \.rawValue) { destination in
                Text(destination.displayName).tag(destination.rawValue)
            }
            ForEach(OAuthProviderID.allCases, id: \.rawValue) { provider in
                Text(oauthPickerLabel(provider)).tag(provider.rawValue)
            }
        }
    }

    @ViewBuilder
    private var destinationsPane: some View {
        Section("Upload destinations") {
            destinationPicker("Image uploads", customTag: "CustomImageUploader",
                              selection: destinationBinding(\.imageDestination))
            destinationPicker("Text uploads", customTag: "CustomTextUploader",
                              selection: destinationBinding(\.textDestination))
            destinationPicker("File & video uploads", customTag: "CustomFileUploader",
                              selection: destinationBinding(\.fileDestination))
            Text("Screenshots use the image destination; recordings and other files the "
                 + "file destination. Until a separate custom uploader is chosen below, text "
                 + "and file uploads follow the image destination.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if [task.imageDestination, task.textDestination, task.fileDestination]
            .contains(where: { Self.customUploaderTags.contains($0) }) {
            customUploaderSection
        }
        ForEach(configurableDestinations, id: \.self) { destination in
            Section(destinationDisplayName(destination)) {
                simpleHostFields(for: destination)
                cloudHostFields(for: destination)
                oauthFields(for: destination)
            }
        }
        Section("Upload behavior") {
            Toggle("Disable all uploads", isOn: configBinding(\.disableUpload))
            TextField("Maximum simultaneous uploads (1–25)",
                      value: clampedConfigBinding(\.uploadLimit, 1...25), format: .number)
            Toggle("Retry failed uploads", isOn: configBinding(\.retryUpload))
            if config.retryUpload {
                TextField("Retry attempts (1–10)",
                          value: clampedConfigBinding(\.maxUploadFailRetry, 1...10), format: .number)
            }
            Toggle("Warn before uploading more than 10 files", isOn: configBinding(\.showMultiUploadWarning))
            Toggle("Warn before uploading files over 100 MB", isOn: configBinding(\.showLargeFileSizeWarning))
        }
        Section("File upload naming") {
            Toggle("Rename uploads with the name pattern", isOn: taskBinding(\.fileUploadUseNamePattern))
            Toggle("Replace problematic characters (spaces → underscores)",
                   isOn: taskBinding(\.fileUploadReplaceProblematicCharacters))
            Toggle("Use custom time zone in name patterns", isOn: taskBinding(\.useCustomTimeZone))
            if task.useCustomTimeZone {
                TextField("Time zone identifier", text: taskBinding(\.customTimeZoneIdentifier))
                Text("Examples: UTC, America/New_York, Asia/Tokyo. Unknown identifiers fall back to local time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Clipboard upload") {
            Toggle("Copied URL: upload its contents", isOn: taskBinding(\.clipboardUploadURLContents))
            Toggle("Copied URL: shorten instead of uploading", isOn: taskBinding(\.clipboardUploadShortenURL))
            Toggle("Copied URL: share instead of uploading", isOn: taskBinding(\.clipboardUploadShareURL))
            Toggle("Copied folder: upload an HTML index", isOn: taskBinding(\.clipboardUploadAutoIndexFolder))
            Toggle("Clear clipboard after clipboard upload", isOn: taskBinding(\.autoClearClipboard))
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
        Section("URL processing") {
            TextField("Clipboard format", text: taskBinding(\.clipboardContentFormat))
                .font(.body.monospaced())
            TextField("Open-URL format", text: taskBinding(\.openURLFormat))
                .font(.body.monospaced())
            TextField("Notification format", text: taskBinding(\.balloonTipContentFormat))
                .font(.body.monospaced())
            Text("$result is replaced with the final URL — e.g. ![]($result) for Markdown.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Copy URL early (before shortening and formatting)", isOn: taskBinding(\.earlyCopyURL))
            Toggle("Force HTTPS in result URLs", isOn: taskBinding(\.resultForceHTTPS))
            Toggle("Regex-replace result URLs", isOn: taskBinding(\.urlRegexReplace))
            if task.urlRegexReplace {
                TextField("Pattern", text: taskBinding(\.urlRegexReplacePattern))
                    .font(.body.monospaced())
                TextField("Replacement ($1 for groups)", text: taskBinding(\.urlRegexReplaceReplacement))
                    .font(.body.monospaced())
            }
            TextField("Auto-shorten URLs longer than (characters, 0 = off)",
                      value: clampedBinding(\.autoShortenURLLength, 0...4096), format: .number)
        }
    }

    private func oauthPickerLabel(_ id: OAuthProviderID) -> String {
        // hosts without baked-in (or override) credentials read "unavailable"
        UploadersConfig.load().isConfigured(id) ? id.displayName : "\(id.displayName) — unavailable"
    }

    private func oauthBinding(_ id: OAuthProviderID,
                              _ keyPath: WritableKeyPath<OAuthAppCredentials, String>) -> Binding<String> {
        Binding(
            get: { (UploadersConfig.load().oauthApps[id.rawValue] ?? OAuthAppCredentials())[keyPath: keyPath] },
            set: { value in
                var config = UploadersConfig.load()
                var creds = config.oauthApps[id.rawValue] ?? OAuthAppCredentials()
                creds[keyPath: keyPath] = value
                config.oauthApps[id.rawValue] = creds
                try? config.save()
            }
        )
    }

    /// Per-type custom uploader pickers. Text and file uploads can follow the
    /// image uploader (empty selection) or pin their own .sxcu.
    @ViewBuilder
    private var customUploaderSection: some View {
        Section("Custom uploaders") {
            let uploaders = CustomUploaderStore.list()
            if uploaders.isEmpty {
                Text("No custom uploaders imported. Use Import… in Settings → Custom Uploader — any community .sxcu file works.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if task.imageDestination == "CustomImageUploader" {
                    Picker("Image uploader", selection: uploaderBinding()) {
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if task.textDestination == "CustomTextUploader" {
                    Picker("Text uploader", selection: uploaderBinding(\.activeTextCustomUploader)) {
                        Text("Same as image").tag("")
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if task.fileDestination == "CustomFileUploader" {
                    Picker("File uploader", selection: uploaderBinding(\.activeFileCustomUploader)) {
                        Text("Same as image").tag("")
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            }
        }
    }

    /// End-user OAuth setup is one-click: SwiftX ships the app credentials, so
    /// the user only signs in and approves. The client ID/secret fields are for
    /// developers / power users and stay hidden in an Advanced disclosure.
    @ViewBuilder
    private func oauthFields(for destination: String) -> some View {
        if let id = OAuthProviderID(rawValue: destination) {
            let configured = UploadersConfig.load().isConfigured(id)
            let connected = OAuthTokenStore.isConnected(id)

            if configured {
                HStack {
                    Button(connected ? "Reconnect \(id.displayName)…" : "Connect \(id.displayName)…") {
                        OAuthConnectCoordinator.shared.connect(id)
                    }
                    if connected {
                        Label("Connected", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Button("Disconnect") { OAuthTokenStore.delete(for: id) }
                    }
                }
                Text(connected
                     ? "SwiftX is authorized to upload to your \(id.displayName) account."
                     : "Sign in with your \(id.displayName) account to authorize SwiftX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(id.displayName) uploads are unavailable in this build (no registered app). Supply your own OAuth app below, or use a build that ships \(id.displayName) credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Developers / power users who want their own app + quota. Redirect
            // URI to register with the host: http://127.0.0.1 (loopback).
            DisclosureGroup("Advanced: use your own \(id.displayName) OAuth app") {
                TextField("Client ID", text: oauthBinding(id, \.clientID))
                SecureField("Client secret (blank for PKCE-only apps)", text: oauthBinding(id, \.clientSecret))
                Text("Register the redirect URI as http://127.0.0.1 (loopback). Overrides the built-in app for this host.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Credential fields for the cloud storage and token-auth destinations.
    @ViewBuilder
    private func cloudHostFields(for destination: String) -> some View {
        switch destination {
        case "AmazonS3":
            TextField("Access key ID", text: s3Binding(\.accessKeyID))
            SecureField("Secret access key", text: s3Binding(\.secretAccessKey))
            TextField("Region", text: s3Binding(\.region))
            TextField("Bucket", text: s3Binding(\.bucket))
            TextField("Object prefix", text: s3Binding(\.objectPrefix))
            TextField("Custom endpoint (optional, for S3-compatible hosts)", text: s3Binding(\.endpoint))
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
    private func simpleHostFields(for destination: String) -> some View {
        switch SimpleHostDestination(rawValue: destination) {
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
/// needed for formats VideoToolbox can't encode (WebM VP9/VP8, animated WebP,
/// APNG) and for the Video Converter tool.
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
            AppLog.app.error("Could not launch ffmpeg install: \(error.localizedDescription, privacy: .public)")
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
