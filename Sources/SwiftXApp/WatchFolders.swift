// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
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
                NSLog("Watch folder skipped, directory missing: %@", folder.folderPath)
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
                    NSLog("Watch folder move failed: %@", error.localizedDescription)
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
        Section("Watch folders") {
            Toggle("Watch folders and upload new files", isOn: Binding(
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
                        Button("Remove") {
                            task.watchFolderList.remove(at: index)
                            apply()
                        }
                    }
                    TextField("File name filter (e.g. *.png, empty = all):", text: Binding(
                        get: { task.watchFolderList[index].filter },
                        set: { task.watchFolderList[index].filter = $0; apply() }
                    ))
                    Toggle("Include subdirectories", isOn: Binding(
                        get: { task.watchFolderList[index].includeSubdirectories },
                        set: { task.watchFolderList[index].includeSubdirectories = $0; apply() }
                    ))
                    Toggle("Move files to screenshots folder before upload", isOn: Binding(
                        get: { task.watchFolderList[index].moveFilesToScreenshotsFolder },
                        set: { task.watchFolderList[index].moveFilesToScreenshotsFolder = $0; apply() }
                    ))
                }
                .padding(.vertical, 4)
            }

            Button("Add Folder…") {
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
