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
import UpdateKit
import UploadKit

enum TimeRange: String, CaseIterable {
    case any = "Any time"
    case today = "Today"
    case week = "Last 7 days"
    case month = "Last 30 days"

    /// Localized label; rawValue stays untouched as identity.
    var title: String {
        switch self {
        case .any: L10n.t("main.timerange.any")
        case .today: L10n.t("main.timerange.today")
        case .week: L10n.t("main.timerange.week")
        case .month: L10n.t("main.timerange.month")
        }
    }

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
                TextField(L10n.t("main.search_placeholder"), text: $search)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .fixedSize()
                Toggle(isOn: $favoritesOnly) {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                }
                .toggleStyle(.button)
                .help(L10n.t("main.show_favorites_only"))
                Picker("", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag("ListView")
                    Image(systemName: "square.grid.2x2").tag("ThumbnailView")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Menu {
                    Button(L10n.t("main.import_history")) { importHistory() }
                    Button(L10n.t("main.import_folder")) { importFolder() }
                    Button(L10n.t("main.statistics")) { showStats() }
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
                .help(L10n.t("main.settings"))
            }
            .padding(8)

            UploadTaskRows()

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(search.isEmpty && !favoritesOnly && timeRange == .any
                         ? L10n.t("main.empty_placeholder") : L10n.t("main.no_matches"))
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
        Button(item.isFavorite ? L10n.t("main.remove_favorite") : L10n.t("main.add_favorite")) {
            HistoryStore.shared.setFavorite(id: item.id, !item.isFavorite)
        }
        Divider()
        if !item.url.isEmpty {
            Button(L10n.t("notification.action.copy_url")) { copyString(item.url) }
            Button(L10n.t("main.open_url")) {
                if let url = URL(string: item.url) { NSWorkspace.shared.open(url) }
            }
        }
        if FileManager.default.fileExists(atPath: item.filePath) {
            Button(L10n.t("common.show_in_finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.filePath)])
            }
            Button(L10n.t("main.copy_file_path")) { copyString(item.filePath) }
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
        panel.message = L10n.t("main.import_folder_message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let imported = HistoryStore.shared.appendAll(HistoryImport.items(fromFolder: url))
        Notifier.notify(title: L10n.t("main.import_folder_title"),
                        body: L10n.t("main.import_items_body", imported))
    }

    /// C# History.json/xml migration (HistoryManagerJSON/XML loaders).
    private func importHistory() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .xml]
        panel.message = L10n.t("main.import_history_message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = HistoryStore.shared.appendAll(try HistoryImport.items(fromFile: url))
            Notifier.notify(title: L10n.t("main.import_history_title"),
                            body: L10n.t("main.import_items_body", imported))
        } catch {
            Notifier.notify(title: L10n.t("main.import_history_failed"), body: error.localizedDescription)
        }
    }

    private func showStats() {
        // ponytail: loads every row to group in memory, same as C#; stream via
        // SQL GROUP BY if million-row databases ever show up
        let all = HistoryStore.shared.recent(limit: Int(Int32.max))
        ToolWindows.present(title: L10n.t("main.history_stats_title"), resizable: true,
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
                Button(L10n.t("common.copy")) {
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

/// Sidebar grouping. Twelve flat rows read as one undifferentiated list; the
/// groups say which question each pane answers, and let the high-traffic panes
/// (hotkeys, capture) sit near the top without losing the setup panes.
enum SettingsPaneGroup: String, CaseIterable, Identifiable {
    case app = "App"
    case capture = "Capture"
    case sharing = "Sharing"
    case automation = "Automation"
    case about = "About"

    var id: String { rawValue }

    /// Localized label; rawValue stays untouched as identity.
    var title: String {
        switch self {
        case .app: L10n.t("settings.group.app")
        case .capture: L10n.t("settings.group.capture")
        case .sharing: L10n.t("settings.group.sharing")
        case .automation: L10n.t("settings.group.automation")
        case .about: L10n.t("settings.group.about")
        }
    }

    var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.group == self }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    // rawValues are identity (SettingsNavigator, restored selection); the
    // sidebar order comes from `allCases`, so reordering here reorders the UI
    case general = "General"
    case menuBar = "Menu Bar"
    case hotkeys = "Hotkeys"
    case notifications = "Notifications"
    case capture = "Capture"
    case recording = "Recording"
    case destinations = "Destinations"
    case uploads = "Uploads"
    case customUploader = "Custom Uploader"
    case actions = "Actions"
    case watchFolders = "Watch Folders"
    case updates = "Updates"
    case about = "About"

    var id: String { rawValue }

    var group: SettingsPaneGroup {
        switch self {
        case .general, .menuBar, .hotkeys, .notifications: .app
        case .capture, .recording: .capture
        case .destinations, .uploads, .customUploader: .sharing
        case .actions, .watchFolders: .automation
        case .updates, .about: .about
        }
    }

    /// Localized label; rawValue stays untouched as identity.
    var title: String {
        switch self {
        case .general: L10n.t("settings.pane.general")
        case .menuBar: L10n.t("settings.pane.menu_bar")
        case .notifications: L10n.t("settings.pane.notifications")
        case .capture: L10n.t("settings.pane.capture")
        case .recording: L10n.t("settings.pane.recording")
        case .actions: L10n.t("settings.pane.actions")
        case .watchFolders: L10n.t("settings.pane.watch_folders")
        case .destinations: L10n.t("settings.pane.destinations")
        case .uploads: L10n.t("settings.pane.uploads")
        case .customUploader: L10n.t("settings.pane.custom_uploader")
        case .hotkeys: L10n.t("settings.pane.hotkeys")
        case .updates: L10n.t("settings.pane.updates")
        case .about: L10n.t("settings.pane.about")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .notifications: "bell.badge"
        case .capture: "camera.viewfinder"
        case .recording: "record.circle"
        case .actions: "terminal"
        case .watchFolders: "folder.badge.gearshape"
        case .destinations: "square.and.arrow.up"
        case .uploads: "arrow.up.circle"
        case .customUploader: "wrench.and.screwdriver"
        case .hotkeys: "keyboard"
        case .updates: "arrow.triangle.2.circlepath"
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

/// Updates pane: check/install controls, cadence, and Homebrew handoff.
struct UpdatesView: View {
    @ObservedObject private var updater = UpdateManager.shared
    @State private var config = ApplicationConfig.load()

    private var updateActionInFlight: Bool {
        switch updater.state {
        case .checking, .downloading: return true
        default: return false
        }
    }

    @ViewBuilder private var updateStatusRow: some View {
        switch updater.state {
        case .idle:
            LabeledContent(L10n.t("settings.updates.status")) { Text(L10n.t("settings.updates.not_checked")) }
        case .checking:
            LabeledContent(L10n.t("settings.updates.status")) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("settings.updates.checking"))
                }
            }
        case .upToDate(let date):
            LabeledContent(L10n.t("settings.updates.status")) {
                Text(L10n.t("settings.updates.up_to_date", date.formatted(.relative(presentation: .named))))
            }
        case .available(let update):
            LabeledContent(L10n.t("settings.updates.status")) {
                HStack(spacing: 8) {
                    Text(L10n.t("settings.updates.version_available", String(describing: update.version)))
                    Link(L10n.t("settings.updates.release_notes"), destination: update.release.htmlURL)
                }
            }
        case .downloading:
            LabeledContent(L10n.t("settings.updates.status")) {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("settings.updates.downloading"))
                }
            }
        case .installed(let installedVersion):
            LabeledContent(L10n.t("settings.updates.status")) {
                HStack(spacing: 8) {
                    Text(L10n.t("settings.updates.installed_relaunch", String(describing: installedVersion)))
                    Button(L10n.t("settings.updates.relaunch_now")) { updater.relaunchNow() }
                }
            }
        case .failed(let message):
            LabeledContent(L10n.t("settings.updates.status")) {
                Text(message).foregroundStyle(.red)
            }
        }
    }

    var body: some View {
        Section {
            updateStatusRow
            Picker(L10n.t("settings.updates.check_automatically"), selection: $config.field(\.updateCheckFrequency)) {
                ForEach(UpdateCheckFrequency.allCases, id: \.rawValue) { frequency in
                    let key = "settings.updates.frequency.\(frequency.rawValue)"
                    Text(L10n.t(key)).tag(frequency.rawValue)
                }
            }
            .pickerStyle(.menu)
            if updater.isHomebrewManaged {
                LabeledContent(L10n.t("settings.updates.managed_by_homebrew")) {
                    HStack(spacing: 8) {
                        Text(UpdateManager.brewUpgradeCommand)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                        Button(L10n.t("settings.updates.copy_command")) { updater.copyBrewCommand() }
                    }
                }
            } else {
                Toggle(L10n.t("settings.updates.auto_install"),
                       isOn: $config.field(\.updateAutoInstall))
            }
        } footer: {
            // footers render below the grouped box, so the buttons escape the row card
            HStack {
                Spacer()
                Button(L10n.t("settings.updates.check_for_updates")) { updater.checkFromMenu() }
                    .disabled(updateActionInFlight)
                if case .available = updater.state, !updater.isHomebrewManaged {
                    Button(updater.canSelfInstall
                           ? L10n.t("settings.updates.install_update")
                           : L10n.t("settings.updates.open_release_page")) {
                        if updater.canSelfInstall {
                            updater.installCurrentUpdate()
                        } else {
                            updater.openReleasePage()
                        }
                    }
                    Button(L10n.t("settings.updates.skip_version")) { updater.skipCurrentUpdate() }
                }
            }
            .padding(.top, 4)
        }
    }
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
                    Text(L10n.t("settings.about.version", version)).foregroundStyle(.secondary)
                    Text("© 2026 RetroHazard").font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Link(L10n.t("settings.about.project_page"), destination: URL(string: "https://github.com/RetroHazard/SwiftX")!)
                        Link(L10n.t("settings.about.report_issue"), destination: URL(string: "https://github.com/RetroHazard/SwiftX/issues")!)
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        Section(L10n.t("settings.about.section.credits")) {
            LabeledContent(L10n.t("settings.about.developed_by")) {
                Link("RetroHazard", destination: URL(string: "https://github.com/RetroHazard")!)
            }
            LabeledContent(L10n.t("settings.about.derived_from")) {
                Link("ShareX", destination: URL(string: "https://github.com/ShareX/ShareX")!)
            }
            Text(L10n.t("settings.about.not_affiliated"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L10n.t("settings.about.section.license")) {
            // GPL v3 §5(d) copyright notice: SwiftX's own plus the preserved
            // upstream notice, matching the source-file header wording
            Text("© 2026 RetroHazard.\nContains code derived from ShareX, © 2007–2026 ShareX Team.")
                .font(.callout)
            Text(L10n.t("settings.about.license_body"))
                .font(.callout)
                .foregroundStyle(.secondary)
            // SwiftUI Link won't open file:// URLs; NSWorkspace opens the
            // bundled LICENSE (or the gnu.org fallback) reliably
            Button(L10n.t("settings.about.view_license")) {
                NSWorkspace.shared.open(licenseURL)
            }
        }
    }
}

/// Hard-locks the settings sidebar at a fixed width: no divider drag, no
/// collapse. NavigationSplitView's width modifiers are advisory in a
/// hand-hosted NSWindow, so climb from inside the sidebar column to the
/// underlying NSSplitViewItem and pin its thickness directly. If SwiftUI's
/// internal hierarchy ever stops matching, the walk finds nothing and the
/// sidebar just stays SwiftUI-managed.
private struct SidebarLock: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // defer until the view is parented into the split view hierarchy
        DispatchQueue.main.async { lock(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { lock(from: nsView) } // SwiftUI may reconfigure items
    }

    private func lock(from view: NSView) {
        var ancestor = view.superview
        while let current = ancestor, !(current is NSSplitView) { ancestor = current.superview }
        guard let splitView = ancestor as? NSSplitView,
              let controller = splitView.delegate as? NSSplitViewController,
              let sidebar = controller.splitViewItems.first
        else { return }
        sidebar.minimumThickness = width
        sidebar.maximumThickness = width
        sidebar.canCollapse = false
    }
}

struct SettingsView: View {
    @State private var config = ApplicationConfig.load()
    @State private var task = TaskSettings.load()
    @ObservedObject private var nav = SettingsNavigator.shared
    // UploadersConfig/OAuthTokenStore are read straight from disk/Keychain on
    // every body evaluation, so nothing marks the view dirty when they change
    // out from under it (connecting, disconnecting). Bumping this forces
    // SwiftUI to re-evaluate oauthFields.
    @State private var oauthRefresh = 0
    // Dragging the divider past the sidebar's minimum collapses the column,
    // and with the sidebar toggle removed there is no way back. Track
    // visibility so a collapse can be snapped back open (see body).
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    /// Toggle + file picker pair for the C# custom notification sound slots.
    @ViewBuilder
    private func customSoundRows(_ label: String,
                                 use: WritableKeyPath<TaskSettings, Bool>,
                                 path: WritableKeyPath<TaskSettings, String>) -> some View {
        Toggle(label, isOn: $task.field(use))
        if task[keyPath: use] {
            LabeledContent(L10n.t("settings.notifications.sound_file")) {
                HStack {
                    Text(task[keyPath: path].isEmpty
                         ? L10n.t("common.none_chosen")
                         : (task[keyPath: path] as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L10n.t("common.choose")) { chooseSoundFile(path) }
                }
            }
        }
    }

    /// Language lookups are pointed at the new table only on launch, so offer
    /// a relaunch. Quit-then-open with a delay: the flock in SingleInstance
    /// would make an instance opened before we exit bail out immediately.
    private func promptRelaunch() {
        let alert = NSAlert()
        alert.messageText = L10n.t("settings.general.language.restart_title")
        alert.informativeText = L10n.t("settings.general.language.restart_body")
        alert.addButton(withTitle: L10n.t("settings.general.language.relaunch_now"))
        alert.addButton(withTitle: L10n.t("settings.general.language.later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            let script = "sleep 1; /usr/bin/open \"\(bundlePath)\""
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
            relauncher.arguments = ["-c", script]
            try? relauncher.run()
        }
        NSApp.terminate(nil)
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
            Notifier.notify(title: L10n.t("settings.general.export_failed"), body: error.localizedDescription,
                            event: .error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .init(filenameExtension: "sxb") ?? .zip]
        panel.message = L10n.t("settings.general.import_panel_message")
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
            Notifier.notify(title: L10n.t("settings.general.import_failed"), body: error.localizedDescription,
                            event: .error)
            return
        }

        if SettingsBackup.isWindowsShareXBackup(extractedAt: staging) {
            importWindowsBackup(extractedAt: staging, named: url.lastPathComponent)
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.t("settings.general.replace_title")
        alert.informativeText = L10n.t("settings.general.replace_body")
        alert.addButton(withTitle: L10n.t("settings.general.replace"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try SettingsBackup.restore(from: url)
            reloadAfterImport()
            Notifier.notify(title: L10n.t("settings.general.restored_title"), body: url.lastPathComponent)
        } catch {
            Notifier.notify(title: L10n.t("settings.general.import_failed"), body: error.localizedDescription,
                            event: .error)
        }
    }

    /// Windows ShareX .sxb: maps what has a macOS equivalent onto the current
    /// settings (a merge, unlike the native replace) and offers to bring the
    /// backup's upload history along.
    private func importWindowsBackup(extractedAt staging: URL, named name: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("settings.general.sharex_import_title")
        alert.informativeText = L10n.t("settings.general.sharex_import_body", name)
        alert.addButton(withTitle: L10n.t("settings.general.import"))
        alert.addButton(withTitle: L10n.t("settings.general.import_without_history"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
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

            var parts = [L10n.t("settings.general.summary.settings_imported")]
            if !summary.importedUploaders.isEmpty {
                parts.append(L10n.t("settings.general.summary.uploaders",
                                    summary.importedUploaders.count))
            }
            if summary.importedHotkeys > 0 || summary.skippedHotkeys > 0 {
                parts.append(summary.skippedHotkeys > 0
                    ? L10n.t("settings.general.summary.hotkeys_skipped",
                             summary.importedHotkeys, summary.skippedHotkeys)
                    : L10n.t("settings.general.summary.hotkeys", summary.importedHotkeys))
            }
            if importedHistory > 0 {
                parts.append(L10n.t("settings.general.summary.history", importedHistory))
            }
            Notifier.notify(title: L10n.t("settings.general.sharex_imported_title"),
                            body: parts.joined(separator: " "))
        } catch {
            Notifier.notify(title: L10n.t("settings.general.sharex_import_failed"), body: error.localizedDescription,
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

    /// Fixed sidebar width, like System Settings. Wide enough for the longest
    /// English pane title; revisit if a translation needs more room.
    private static let sidebarWidth: CGFloat = 175

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $nav.pane) {
                ForEach(SettingsPaneGroup.allCases) { group in
                    Section(group.title) {
                        // explicit tag: List's implicit selection value is the
                        // String id, which never matches our SettingsPane? binding
                        ForEach(group.panes) { pane in
                            Label(pane.title, systemImage: pane.icon)
                                .tag(pane)
                        }
                    }
                }
            }
            // The column-width modifier alone is advisory in a hand-hosted
            // NSWindow - the split view restores its own position over it and
            // titles ellipsize. The List's frame goes through Auto Layout and
            // is enforced, so pin both; all-equal bounds lock the sidebar and
            // leave the divider with nothing to drag.
            .frame(width: Self.sidebarWidth)
            .navigationSplitViewColumnWidth(min: Self.sidebarWidth, ideal: Self.sidebarWidth,
                                            max: Self.sidebarWidth)
            .background(SidebarLock(width: Self.sidebarWidth))
            // the toggle floats misaligned in a hand-made NSWindow's title bar;
            // a fixed settings sidebar doesn't need collapsing anyway
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Form {
                switch nav.pane ?? .general {
                case .general: generalPane
                case .menuBar: menuBarPane
                case .notifications: notificationsPane
                case .capture: capturePane
                case .recording: recordingPane
                case .actions: ActionsSettingsView()
                case .watchFolders: WatchFoldersSettingsView()
                case .destinations: destinationsPane
                case .uploads: UploadsSettingsView()
                case .customUploader: CustomUploaderEditorView()
                case .hotkeys: HotkeysSettingsView()
                case .updates: UpdatesView()
                case .about: AboutView()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((nav.pane ?? .general).title)
        }
        .frame(minWidth: Self.sidebarWidth + 480, minHeight: 420)
        // a divider drag past the minimum collapses the sidebar; reopen it
        .onChange(of: columnVisibility) {
            if columnVisibility != .all { columnVisibility = .all }
        }
    }

    @ViewBuilder
    private var generalPane: some View {
        Section(L10n.t("settings.general.section.language")) {
            Picker(L10n.t("settings.general.language.picker"),
                   selection: $config.field(\.interfaceLanguage)) {
                Text(L10n.t("settings.general.language.system_default")).tag("")
                ForEach(L10n.availableLanguages, id: \.self) { code in
                    Text(L10n.displayName(for: code)).tag(code)
                }
            }
            .onChange(of: config.interfaceLanguage) { promptRelaunch() }
        }
        // where captures land and what they are called, together: the folder
        // alone left the name and subfolder patterns editable only in JSON
        Section(L10n.t("settings.general.section.saved_files")) {
            LabeledContent(L10n.t("settings.general.screenshots_folder")) {
                HStack {
                    Text(config.screenshotsFolder.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Button(L10n.t("common.choose")) { chooseFolder() }
                    if config.useCustomScreenshotsPath {
                        Button(L10n.t("common.reset")) {
                            config.useCustomScreenshotsPath = false
                            config.customScreenshotsPath = ""
                            try? config.save()
                        }
                    }
                }
            }
            TextField(L10n.t("settings.general.subfolder_pattern"), text: $config.field(\.saveImageSubFolderPattern))
                .font(.body.monospaced())
            TextField(L10n.t("settings.general.name_pattern"), text: $task.field(\.nameFormatPattern))
                .font(.body.monospaced())
            TextField(L10n.t("settings.general.name_pattern_active_window"),
                      text: $task.field(\.nameFormatPatternActiveWindow))
                .font(.body.monospaced())
            Text(L10n.t("settings.general.name_pattern_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(L10n.t("settings.general.file_exist_action"), selection: $task.field(\.fileExistAction)) {
                Text(L10n.t("settings.general.exist_unique")).tag("UniqueName")
                Text(L10n.t("settings.general.exist_ask")).tag("Ask")
                Text(L10n.t("settings.general.exist_overwrite")).tag("Overwrite")
                Text(L10n.t("settings.general.exist_skip")).tag("Cancel")
            }
        }
        Section(L10n.t("settings.general.section.permissions")) {
            PermissionsView()
        }
        Section(L10n.t("settings.general.section.browser_extension")) {
            NativeMessagingSection()
        }
        Section(L10n.t("settings.general.section.backup")) {
            HStack {
                Button(L10n.t("settings.general.export_settings")) { exportSettings() }
                Button(L10n.t("settings.general.import_settings")) { importSettings() }
            }
            Text(L10n.t("settings.general.backup_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menuBarPane: some View {
        Section(L10n.t("settings.menubar.section.icon")) {
            Picker(L10n.t("settings.menubar.left_click"), selection: $config.field(\.trayLeftClickAction)) {
                Text(L10n.t("settings.menubar.action.open_menu")).tag("ToggleTrayMenu")
                Text(L10n.t("settings.menubar.action.open_main_window")).tag("OpenMainWindow")
                Text(L10n.t("settings.menubar.action.capture_region")).tag("RectangleRegion")
                Text(L10n.t("settings.menubar.action.capture_fullscreen")).tag("PrintScreen")
                Text(L10n.t("settings.menubar.action.capture_active_window")).tag("ActiveWindow")
                Text(L10n.t("settings.menubar.action.upload_clipboard")).tag("ClipboardUpload")
                Text(L10n.t("settings.menubar.action.upload_file")).tag("FileUpload")
                Text(L10n.t("settings.menubar.action.image_editor")).tag("ImageEditor")
                Text(L10n.t("settings.menubar.action.open_screenshots_folder")).tag("OpenScreenshotsFolder")
            }
            Text(L10n.t("settings.menubar.right_click_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(L10n.t("settings.menubar.show_progress"), isOn: $config.field(\.trayIconProgressEnabled))
            Toggle(L10n.t("settings.menubar.show_recent"), isOn: $config.field(\.recentTasksShowInTrayMenu))
            if config.recentTasksShowInTrayMenu {
                TextField(L10n.t("settings.menubar.recent_count"),
                          value: $config.field(\.recentTasksMaxCount, in: 1...30), format: .number)
            }
        }
        Section(L10n.t("settings.menubar.section.menu_items")) {
            DisclosureGroup(L10n.t("settings.menubar.menu_items")) {
                ForEach(TrayMenuItemID.allCases, id: \.rawValue) { id in
                    Toggle(id.displayName, isOn: trayItemVisibleBinding(id))
                }
            }
            Text(L10n.t("settings.menubar.menu_items_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // the floating capture toolbar is a second menu surface, not a general
        // app preference - it sat in General next to the language picker, and
        // its name collided with the unrelated Actions pane
        Section(L10n.t("settings.menubar.section.actions_toolbar")) {
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
            Menu(L10n.t("settings.menubar.add_button")) {
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
            Toggle(L10n.t("settings.menubar.lock_toolbar"), isOn: $config.field(\.actionsToolbarLockPosition))
            Toggle(L10n.t("settings.menubar.toolbar_at_launch"), isOn: $config.field(\.actionsToolbarRunAtStartup))
            Text(L10n.t("settings.menubar.toolbar_reopen_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notificationsPane: some View {
        Section(L10n.t("settings.notifications.section.banners")) {
            Toggle(L10n.t("settings.notifications.show_banners"), isOn: $task.field(\.showToastNotificationAfterTaskCompleted))
            Toggle(L10n.t("settings.notifications.suppress_fullscreen"),
                   isOn: $task.field(\.disableNotificationsOnFullscreen))
            Text(L10n.t("settings.notifications.banner_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L10n.t("settings.notifications.section.sounds")) {
            Toggle(L10n.t("settings.notifications.sound_after_capture"), isOn: $task.field(\.playSoundAfterCapture))
            customSoundRows(L10n.t("settings.notifications.custom_capture_sound"),
                            use: \.useCustomCaptureSound, path: \.customCaptureSoundPath)
            Toggle(L10n.t("settings.notifications.sound_after_upload"), isOn: $task.field(\.playSoundAfterUpload))
            customSoundRows(L10n.t("settings.notifications.custom_completion_sound"),
                            use: \.useCustomTaskCompletedSound, path: \.customTaskCompletedSoundPath)
            customSoundRows(L10n.t("settings.notifications.custom_error_sound"),
                            use: \.useCustomErrorSound, path: \.customErrorSoundPath)
        }
    }

    @ViewBuilder
    private var capturePane: some View {
        Section {
            TextField(L10n.t("settings.capture.screenshot_delay"),
                      value: $task.field(\.screenshotDelay, in: 0...60), format: .number)
            Toggle(L10n.t("settings.capture.show_cursor"), isOn: $task.field(\.showCursor))
        }
        // Same component and labels as the after-capture window, driven by the
        // pipeline's own flag set - the previous hand-kept list had drifted to
        // 14 of the 22 implemented tasks and used a second set of translations.
        Section(L10n.t("settings.capture.section.after_capture")) {
            TaskFlagToggles(value: $task.field(\.afterCaptureJob),
                            excluded: AfterCaptureTasks.all.subtracting(AfterCapturePipeline.implemented))
            Text(L10n.t("settings.capture.after_capture_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L10n.t("settings.capture.section.effects")) {
            Toggle(L10n.t("settings.capture.effects_window"), isOn: $task.field(\.showImageEffectsWindowAfterCapture))
            Toggle(L10n.t("settings.capture.effects_region_only"), isOn: $task.field(\.imageEffectOnlyRegionCapture))
            Toggle(L10n.t("settings.capture.effects_random"), isOn: $task.field(\.useRandomImageEffect))
            Text(L10n.t("settings.capture.effects_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L10n.t("settings.capture.section.image_format")) {
            Picker(L10n.t("settings.capture.format"), selection: $task.field(\.imageFormat)) {
                ForEach(ImageFileFormat.allCases, id: \.rawValue) { format in
                    Text(format.rawValue).tag(format.rawValue)
                }
            }
            if task.imageFormat == "JPEG" {
                TextField(L10n.t("settings.capture.jpeg_quality"),
                          value: $task.field(\.imageJPEGQuality, in: 1...100), format: .number)
            }
            if task.imageFormat == "PNG" {
                Picker(L10n.t("settings.capture.png_bit_depth"), selection: $task.field(\.imagePNGBitDepth)) {
                    Text(L10n.t("settings.capture.automatic")).tag("Default")
                    Text(L10n.t("settings.capture.png_32bit")).tag("Bit32")
                    Text(L10n.t("settings.capture.png_24bit")).tag("Bit24")
                }
            }
            if task.imageFormat == "GIF" {
                Picker(L10n.t("settings.capture.gif_palette"), selection: $task.field(\.imageGIFQuality)) {
                    Text(L10n.t("settings.capture.automatic")).tag("Default")
                    Text(L10n.t("settings.capture.gif_256")).tag("Bit8")
                    Text(L10n.t("settings.capture.gif_16")).tag("Bit4")
                    Text(L10n.t("settings.capture.gif_grayscale")).tag("Grayscale")
                }
            }
            Toggle(L10n.t("settings.capture.auto_jpeg"), isOn: $task.field(\.imageAutoUseJPEG))
            if task.imageAutoUseJPEG {
                TextField(L10n.t("settings.capture.auto_jpeg_size"),
                          value: $task.field(\.imageAutoUseJPEGSize, in: 64...16384), format: .number)
                TextField(L10n.t("settings.capture.auto_jpeg_quality"),
                          value: $task.field(\.imageAutoJPEGQuality, in: 1...100), format: .number)
            }
        }
        Section(L10n.t("settings.capture.section.thumbnail")) {
            TextField(L10n.t("settings.capture.thumbnail_width"),
                      value: $task.field(\.thumbnailWidth, in: 0...4096), format: .number)
            TextField(L10n.t("settings.capture.thumbnail_height"),
                      value: $task.field(\.thumbnailHeight, in: 0...4096), format: .number)
            TextField(L10n.t("settings.capture.thumbnail_name"), text: $task.field(\.thumbnailName))
            Toggle(L10n.t("settings.capture.thumbnail_check_size"), isOn: $task.field(\.thumbnailCheckSize))
            Text(L10n.t("settings.capture.thumbnail_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var recordingPane: some View {
        Section(L10n.t("settings.recording.section.video")) {
            Picker(L10n.t("settings.recording.video_codec"), selection: $task.field(\.screenRecordCodec)) {
                Text(L10n.t("settings.recording.codec_h264")).tag("H264")
                Text(L10n.t("settings.recording.codec_hevc")).tag("HEVC")
                Text(L10n.t("settings.recording.codec_vp9")).tag("VP9")
                Text(L10n.t("settings.recording.codec_vp8")).tag("VP8")
                Text(L10n.t("settings.recording.codec_webp")).tag("WEBP")
                Text(L10n.t("settings.recording.codec_apng")).tag("APNG")
            }
            TextField(L10n.t("settings.recording.video_fps"),
                      value: $task.field(\.screenRecordFPS, in: 1...60), format: .number)
            TextField(L10n.t("settings.recording.gif_fps"),
                      value: $task.field(\.gifFPS, in: 1...30), format: .number)
            Toggle(L10n.t("settings.recording.two_pass"),
                   isOn: $task.field(\.screenRecordTwoPassEncoding))
        }
        Section(L10n.t("settings.recording.section.session")) {
            TextField(L10n.t("settings.recording.start_delay"),
                      value: $task.field(\.screenRecordStartDelay, in: 0...60), format: .number)
            Toggle(L10n.t("settings.recording.fixed_duration"), isOn: $task.field(\.screenRecordFixedDuration))
            if task.screenRecordFixedDuration {
                TextField(L10n.t("settings.recording.stop_after"),
                          value: $task.field(\.screenRecordDuration, in: 1...86400), format: .number)
            }
            Toggle(L10n.t("settings.recording.confirm_abort"),
                   isOn: $task.field(\.screenRecordAskConfirmationOnAbort))
            Toggle(L10n.t("settings.recording.show_cursor"), isOn: $task.field(\.screenRecordShowCursor))
        }
        Section(L10n.t("settings.recording.section.audio")) {
            Toggle(L10n.t("settings.recording.system_audio"), isOn: $task.field(\.screenRecordSystemAudio))
            Toggle(L10n.t("settings.recording.microphone"), isOn: $task.field(\.screenRecordMicrophone))
            Text(L10n.t("settings.recording.audio_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(L10n.t("settings.recording.section.external_tools")) {
            FFmpegStatusView()
            TextField(L10n.t("settings.recording.custom_ffmpeg_args"), text: $task.field(\.screenRecordCustomFFmpegArgs))
                .font(.body.monospaced())
            Text(L10n.t("settings.recording.ffmpeg_args_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The three per-type "custom uploader" sentinels (C# enum member names).
    private static let customUploaderTags = DestinationCatalog.customUploaderTags

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
        DestinationCatalog.displayName(for: destination)
    }

    /// Picker rows for a slot: only the hosts that accept that kind of upload,
    /// so YouTube can't be chosen for text and image hosts can't take archives.
    /// A stored destination that doesn't fit the slot (an imported Windows
    /// config, or one set before this filtering existed) still gets a row —
    /// dropping it would silently repoint the slot without saying so.
    @ViewBuilder
    private func destinationPicker(_ label: String, kind: UploadKind,
                                   selection: Binding<String>) -> some View {
        let available = DestinationCatalog.available(for: kind)
        let current = selection.wrappedValue
        Picker(label, selection: selection) {
            ForEach(available) { destination in
                Text(destinationPickerLabel(destination)).tag(destination.id)
            }
            if !available.contains(where: { $0.id == current }) {
                Text(L10n.t("settings.destinations.not_valid_for",
                            destinationDisplayName(current), kind.displayName))
                    .tag(current)
            }
        }
    }

    /// OAuth hosts without credentials read "unavailable"; everything else uses
    /// its plain catalog name.
    private func destinationPickerLabel(_ destination: UploadDestination) -> String {
        guard let id = OAuthProviderID(rawValue: destination.id) else { return destination.displayName }
        return oauthPickerLabel(id)
    }

    @ViewBuilder
    private var destinationsPane: some View {
        Section(L10n.t("settings.destinations.section.upload_destinations")) {
            destinationPicker(L10n.t("settings.destinations.image_uploads"), kind: .image,
                              selection: $task.field(\.imageDestination))
            destinationPicker(L10n.t("settings.destinations.text_uploads"), kind: .text,
                              selection: $task.field(\.textDestination))
            destinationPicker(L10n.t("settings.destinations.file_uploads"), kind: .file,
                              selection: $task.field(\.fileDestination))
            Text(L10n.t("settings.destinations.destinations_hint"))
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
    }

    private func oauthPickerLabel(_ id: OAuthProviderID) -> String {
        // hosts without baked-in (or override) credentials read "unavailable"
        UploadersConfig.load().isConfigured(id)
            ? id.displayName
            : L10n.t("settings.destinations.unavailable_suffix", id.displayName)
    }

    /// Per-type custom uploader pickers. Text and file uploads can follow the
    /// image uploader (empty selection) or pin their own .sxcu.
    @ViewBuilder
    private var customUploaderSection: some View {
        Section(L10n.t("settings.destinations.section.custom_uploaders")) {
            let uploaders = CustomUploaderStore.list()
            if uploaders.isEmpty {
                Text(L10n.t("settings.destinations.no_custom_uploaders"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if task.imageDestination == "CustomImageUploader" {
                    Picker(L10n.t("settings.destinations.image_uploader"), selection: SettingsBinding.onDisk(\UploadersConfig.activeCustomUploader)) {
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if task.textDestination == "CustomTextUploader" {
                    Picker(L10n.t("settings.destinations.text_uploader"), selection: SettingsBinding.onDisk(\UploadersConfig.activeTextCustomUploader)) {
                        Text(L10n.t("settings.destinations.same_as_image")).tag("")
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if task.fileDestination == "CustomFileUploader" {
                    Picker(L10n.t("settings.destinations.file_uploader"), selection: SettingsBinding.onDisk(\UploadersConfig.activeFileCustomUploader)) {
                        Text(L10n.t("settings.destinations.same_as_image")).tag("")
                        ForEach(uploaders, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
            }
        }
    }

    /// OAuth setup is one click: SwiftX ships the app credentials, so the user
    /// only signs in and approves. There is deliberately nothing to fill in —
    /// a build without baked-in credentials just reports the host unavailable.
    @ViewBuilder
    private func oauthFields(for destination: String) -> some View {
        // Read as a dependency so SwiftUI re-evaluates this section when the
        // connect/disconnect state changes.
        let _ = oauthRefresh
        if let id = OAuthProviderID(rawValue: destination) {
            let configured = UploadersConfig.load().isConfigured(id)
            let connected = OAuthTokenStore.isConnected(id)

            if configured {
                HStack {
                    Button(connected
                           ? L10n.t("settings.destinations.reconnect", id.displayName)
                           : L10n.t("settings.destinations.connect", id.displayName)) {
                        Task {
                            await OAuthConnectCoordinator.shared.connect(id)
                            oauthRefresh &+= 1
                        }
                    }
                    if connected {
                        Label(L10n.t("settings.destinations.connected"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Button(L10n.t("settings.destinations.disconnect")) {
                            OAuthTokenStore.delete(for: id)
                            oauthRefresh &+= 1
                        }
                    }
                }
                Text(connected
                     ? L10n.t("settings.destinations.oauth_connected_hint", id.displayName)
                     : L10n.t("settings.destinations.oauth_signin_hint", id.displayName))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.t("settings.destinations.oauth_unavailable_hint",
                            id.displayName, id.displayName))
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
            TextField(L10n.t("settings.destinations.s3_access_key"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.accessKeyID))
            SecureField(L10n.t("settings.destinations.s3_secret_key"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.secretAccessKey))
            TextField(L10n.t("settings.destinations.s3_region"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.region))
            TextField(L10n.t("settings.destinations.s3_bucket"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.bucket))
            TextField(L10n.t("settings.destinations.s3_object_prefix"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.objectPrefix))
            TextField(L10n.t("settings.destinations.s3_endpoint"), text: SettingsBinding.onDisk(\UploadersConfig.amazonS3.endpoint))
        case "BackblazeB2":
            TextField(L10n.t("settings.destinations.b2_key_id"), text: SettingsBinding.onDisk(\UploadersConfig.b2ApplicationKeyId))
            SecureField(L10n.t("settings.destinations.b2_key"), text: SettingsBinding.onDisk(\UploadersConfig.b2ApplicationKey))
            TextField(L10n.t("settings.destinations.b2_bucket"), text: SettingsBinding.onDisk(\UploadersConfig.b2BucketName))
            TextField(L10n.t("settings.destinations.upload_path"), text: SettingsBinding.onDisk(\UploadersConfig.b2UploadPath))
            Toggle(L10n.t("settings.destinations.b2_use_custom_url"), isOn: SettingsBinding.onDisk(\UploadersConfig.b2UseCustomUrl))
            TextField(L10n.t("settings.destinations.b2_custom_url"), text: SettingsBinding.onDisk(\UploadersConfig.b2CustomUrl))
        case "AzureStorage":
            TextField(L10n.t("settings.destinations.azure_account"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageAccountName))
            SecureField(L10n.t("settings.destinations.azure_key"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageAccountAccessKey))
            TextField(L10n.t("settings.destinations.azure_container"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageContainer))
            TextField(L10n.t("settings.destinations.azure_environment"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageEnvironment))
            TextField(L10n.t("settings.destinations.azure_custom_domain"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageCustomDomain))
            TextField(L10n.t("settings.destinations.upload_path"), text: SettingsBinding.onDisk(\UploadersConfig.azureStorageUploadPath))
        case "OwnCloud":
            TextField(L10n.t("settings.destinations.owncloud_server"), text: SettingsBinding.onDisk(\UploadersConfig.ownCloudHost))
            TextField(L10n.t("settings.destinations.owncloud_username"), text: SettingsBinding.onDisk(\UploadersConfig.ownCloudUsername))
            SecureField(L10n.t("settings.destinations.owncloud_password"), text: SettingsBinding.onDisk(\UploadersConfig.ownCloudPassword))
            TextField(L10n.t("settings.destinations.remote_folder"), text: SettingsBinding.onDisk(\UploadersConfig.ownCloudPath))
        case "Seafile":
            TextField(L10n.t("settings.destinations.seafile_api_url"), text: SettingsBinding.onDisk(\UploadersConfig.seafileAPIURL))
            SecureField(L10n.t("settings.destinations.seafile_token"), text: SettingsBinding.onDisk(\UploadersConfig.seafileAuthToken))
            TextField(L10n.t("settings.destinations.seafile_repo_id"), text: SettingsBinding.onDisk(\UploadersConfig.seafileRepoID))
            TextField(L10n.t("settings.destinations.remote_folder"), text: SettingsBinding.onDisk(\UploadersConfig.seafilePath))
        case "Pushbullet":
            SecureField(L10n.t("settings.destinations.pushbullet_token"), text: SettingsBinding.onDisk(\UploadersConfig.pushbulletAPIKey))
            Text(L10n.t("settings.destinations.pushbullet_hint"))
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
            TextField(L10n.t("settings.destinations.pomf_upload_url"), text: SettingsBinding.onDisk(\UploadersConfig.pomf.uploadURL))
            TextField(L10n.t("settings.destinations.pomf_result_url"), text: SettingsBinding.onDisk(\UploadersConfig.pomf.resultURL))
        case .vgyme:
            SecureField(L10n.t("settings.destinations.vgyme_user_key"), text: SettingsBinding.onDisk(\UploadersConfig.vgymeUserKey))
        case .sul:
            SecureField(L10n.t("settings.destinations.sul_api_key"), text: SettingsBinding.onDisk(\UploadersConfig.sulAPIKey))
        case .lobfile:
            SecureField(L10n.t("settings.destinations.lobfile_api_key"), text: SettingsBinding.onDisk(\UploadersConfig.lithiio.userAPIKey))
        case .puush:
            SecureField(L10n.t("settings.destinations.puush_api_key"), text: SettingsBinding.onDisk(\UploadersConfig.puushAPIKey))
        case .chevereto:
            TextField(L10n.t("settings.destinations.chevereto_upload_url"), text: SettingsBinding.onDisk(\UploadersConfig.chevereto.uploadURL))
            SecureField(L10n.t("settings.destinations.chevereto_api_key"), text: SettingsBinding.onDisk(\UploadersConfig.chevereto.apiKey))
            Toggle(L10n.t("settings.destinations.chevereto_direct_url"), isOn: SettingsBinding.onDisk(\UploadersConfig.cheveretoDirectURL))
        case .streamable:
            TextField(L10n.t("settings.destinations.streamable_email"), text: SettingsBinding.onDisk(\UploadersConfig.streamableUsername))
            SecureField(L10n.t("settings.destinations.streamable_password"), text: SettingsBinding.onDisk(\UploadersConfig.streamablePassword))
        case .uguu:
            Text(L10n.t("settings.destinations.uguu_hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Label(ffmpegPath != nil ? L10n.t("settings.recording.ffmpeg_installed")
                                        : L10n.t("settings.recording.ffmpeg_not_installed"),
                      systemImage: ffmpegPath != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(ffmpegPath != nil ? .green : .red)
                Text(ffmpegPath ?? L10n.t("settings.recording.ffmpeg_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if ffmpegPath == nil {
                if FFmpeg.homebrewPath != nil {
                    Button(L10n.t("settings.recording.install_homebrew")) { installViaHomebrew() }
                } else {
                    Button(L10n.t("settings.recording.get_homebrew")) {
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
            name: L10n.t("settings.general.permission.screen_recording"),
            detail: L10n.t("settings.general.permission.screen_recording_detail"),
            granted: screenRecording,
            request: { CGRequestScreenCaptureAccess() },
            settingsAnchor: "Privacy_ScreenCapture"
        )
        permissionRow(
            name: L10n.t("settings.general.permission.accessibility"),
            detail: L10n.t("settings.general.permission.accessibility_detail"),
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
                Button(L10n.t("settings.general.permission.request")) { request() }
                Button(L10n.t("settings.general.permission.open_system_settings")) {
                    let url = "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)"
                    NSWorkspace.shared.open(URL(string: url)!)
                }
            }
        }
    }
}
