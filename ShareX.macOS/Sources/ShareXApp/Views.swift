// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import SwiftUI
import ApplicationServices
import SharedKit
import UploadKit

struct MainWindowView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Task queue will appear here (Phase 4)")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
