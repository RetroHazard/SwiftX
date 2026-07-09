// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Owns the single active screen recording. Start actions toggle: invoking
// one while recording stops the recording instead (matches C# hotkey feel).

import AppKit
import CaptureKit
import HistoryKit
import SharedKit

@MainActor
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    private var activeRecorder: ScreenRecorder?
    private var activeFormat: RecordingFormat = .movie(hevc: false)
    var isRecording: Bool { activeRecorder != nil }
    /// AppDelegate hook: refresh menu titles and the status item icon.
    var onStateChange: (() -> Void)?

    func toggleRegion(gif: Bool) {
        if isRecording { stop(); return }
        Task {
            guard let rect = await RegionSelectController().selectRegion() else { return }
            // let the compositor remove the overlay before the stream starts
            try? await Task.sleep(for: .milliseconds(80))
            await begin(target: .region(rect), gif: gif)
        }
    }

    func toggleDisplay(gif: Bool) {
        if isRecording { stop(); return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        Task { await begin(target: .display(screen), gif: gif) }
    }

    func toggleActiveWindow(gif: Bool) {
        if isRecording { stop(); return }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        Task { await begin(target: .frontmostWindow(pid), gif: gif) }
    }

    func stop() {
        guard let recorder = activeRecorder else { return }
        activeRecorder = nil
        onStateChange?()
        let format = activeFormat
        Task {
            do {
                let url = try await recorder.stop()
                finish(url: url, format: format)
            } catch {
                Notifier.notify(title: "Recording failed", body: error.localizedDescription)
            }
        }
    }

    func abort() {
        guard let recorder = activeRecorder else { return }
        activeRecorder = nil
        onStateChange?()
        Task { await recorder.abort() }
    }

    private func begin(target: ScreenRecorder.Target, gif: Bool) async {
        let settings = TaskSettings.load()
        let config = ApplicationConfig.load()
        let format: RecordingFormat = gif
            ? .gif
            : .movie(hevc: settings.screenRecordCodec.uppercased() == "HEVC")
        let fps = gif ? settings.gifFPS : settings.screenRecordFPS
        let url = SavePath.screenshotURL(config: config, task: settings, fileExtension: format.fileExtension)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            activeRecorder = try await ScreenRecorder.start(target: target, format: format, fps: fps, outputURL: url)
            activeFormat = format
            onStateChange?()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Recording failed"
            alert.informativeText = error.localizedDescription
                + "\n\nIf this is a permission problem, grant Screen Recording access in ShareX Settings."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func finish(url: URL, format: RecordingFormat) {
        var item = HistoryItem()
        item.fileName = url.lastPathComponent
        item.filePath = url.path
        item.type = format == .gif ? "Image" : "File"
        item.host = "File"
        HistoryStore.shared.append(item)
        Notifier.notify(title: "Recording saved", body: url.lastPathComponent)

        let tasks = TaskSettings.load().afterCaptureJob
        if tasks.contains(.copyFilePathToClipboard) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(url.path, forType: .string)
        }
        if tasks.contains(.showInExplorer) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        if tasks.contains(.uploadImageToHost) {
            UploadCoordinator.uploadFile(at: url)
        }
    }
}
