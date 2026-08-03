// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Watch folders: new files in monitored directories wait for their size to
// settle, optionally move to the screenshots folder, then upload (the C#
// WatchFolderManager pipeline).

import AppKit
import SharedKit
import SwiftUI

@MainActor
final class WatchFolderCenter {
    static let shared = WatchFolderCenter()

    private var watchers: [FolderWatcher] = []

    /// (Re)builds all watchers from TaskSettings; call at launch and after edits.
    func applySettings() {
        watchers.forEach { $0.stop() }
        watchers.removeAll()

        let settings = TaskSettings.load()
        guard settings.watchFolderEnabled else { return }
        for folder in settings.watchFolderList where !folder.folderPath.isEmpty {
            let watcher = FolderWatcher(
                path: folder.folderPath,
                includeSubdirectories: folder.includeSubdirectories,
                filter: folder.filter
            ) { path in
                MainActor.assumeIsolated { Self.shared.process(path: path, folder: folder) }
            }
            if let watcher {
                watchers.append(watcher)
            } else {
                AppLog.upload.warning("Watch folder skipped, directory missing: \(folder.folderPath, privacy: .public)")
            }
        }
    }

    private func process(path: String, folder: WatchFolderSettings) {
        Task { @MainActor in
            guard await FolderWatcher.waitUntilStable(path: path) else { return }
            var url = URL(fileURLWithPath: path)
            if folder.moveFilesToScreenshotsFolder {
                let screenshots = ApplicationConfig.load().screenshotsFolder
                try? FileManager.default.createDirectory(at: screenshots, withIntermediateDirectories: true)
                var destination = screenshots.appendingPathComponent(url.lastPathComponent)
                // C# HandleExistsFile: number the copy instead of overwriting
                var counter = 1
                let base = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                while FileManager.default.fileExists(atPath: destination.path) {
                    counter += 1
                    destination = screenshots.appendingPathComponent("\(base) (\(counter))")
                        .appendingPathExtension(ext)
                }
                do {
                    try FileManager.default.moveItem(at: url, to: destination)
                    url = destination
                } catch {
                    AppLog.upload.error("Watch folder move failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
            UploadCoordinator.uploadFile(at: url)
        }
    }
}

struct WatchFoldersSettingsView: View {
    @State private var task = TaskSettings.load()

    var body: some View {
        Section(L10n.t("settings.watchfolders.title")) {
            Toggle(L10n.t("settings.watchfolders.enable"), isOn: Binding(
                get: { task.watchFolderEnabled },
                set: { task.watchFolderEnabled = $0; apply() }
            ))

            ForEach(task.watchFolderList.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(task.watchFolderList[index].folderPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(L10n.t("common.remove")) {
                            task.watchFolderList.remove(at: index)
                            apply()
                        }
                    }
                    TextField(L10n.t("settings.watchfolders.filter"), text: Binding(
                        get: { task.watchFolderList[index].filter },
                        set: { task.watchFolderList[index].filter = $0; apply() }
                    ))
                    Toggle(L10n.t("settings.watchfolders.include_subdirectories"), isOn: Binding(
                        get: { task.watchFolderList[index].includeSubdirectories },
                        set: { task.watchFolderList[index].includeSubdirectories = $0; apply() }
                    ))
                    Toggle(L10n.t("settings.watchfolders.move_to_screenshots"), isOn: Binding(
                        get: { task.watchFolderList[index].moveFilesToScreenshotsFolder },
                        set: { task.watchFolderList[index].moveFilesToScreenshotsFolder = $0; apply() }
                    ))
                }
                .padding(.vertical, 4)
            }

            Button(L10n.t("settings.watchfolders.add_folder")) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                NSApp.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let url = panel.url else { return }
                var folder = WatchFolderSettings()
                folder.folderPath = url.path
                task.watchFolderList.append(folder)
                apply()
            }
        }
    }

    private func apply() {
        try? task.save()
        WatchFolderCenter.shared.applySettings()
    }
}
