// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Owns the single active screen recording. Start actions toggle: invoking
// one while recording stops the recording, and invoking one during the start
// countdown cancels it (matches C# hotkey feel). A RecordingHUD (border +
// control strip) accompanies every session.

import AppKit
import CaptureKit
import HistoryKit
import SharedKit

@MainActor
final class RecordingCoordinator {
    static let shared = RecordingCoordinator()

    private var activeRecorder: ScreenRecorder?
    private var activeFormat: RecordingFormat = .movie(hevc: false)
    /// VP9/VP8/WebP/APNG record H.264 first, then transcode via ffmpeg on stop.
    private var transcodeTarget: FFmpeg.TranscodeFormat?
    private var hud: RecordingHUD?
    /// Auto-stop for ScreenRecordFixedDuration; cancelled on manual stop/abort.
    private var autoStopTask: Task<Void, Never>?
    /// True from a start action until the stream is live (covers the
    /// ScreenRecordStartDelay countdown); a toggle or abort during that
    /// window cancels the pending start via startCancelled.
    private var isStarting = false
    private var startCancelled = false
    var isRecording: Bool { activeRecorder != nil }
    var isPaused: Bool { activeRecorder?.isPaused ?? false }
    /// AppDelegate hook: refresh menu titles and the status item icon.
    var onStateChange: (() -> Void)?

    func togglePause() {
        guard let recorder = activeRecorder else { return }
        recorder.isPaused ? recorder.resume() : recorder.pause()
        hud?.setPaused(recorder.isPaused)
        onStateChange?()
    }

    func toggleRegion(gif: Bool) {
        if consumeToggleWhileActive() { return }
        Task {
            guard let rect = await RegionSelectController().selectRegion() else { return }
            // let the compositor remove the overlay before the stream starts
            try? await Task.sleep(for: .milliseconds(80))
            await begin(target: .region(rect), gif: gif)
        }
    }

    func toggleDisplay(gif: Bool) {
        if consumeToggleWhileActive() { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        Task { await begin(target: .display(screen), gif: gif) }
    }

    func toggleActiveWindow(gif: Bool) {
        if consumeToggleWhileActive() { return }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        Task { await begin(target: .frontmostWindow(pid), gif: gif) }
    }

    /// Toggle semantics: recording -> stop; counting down -> cancel the start.
    private func consumeToggleWhileActive() -> Bool {
        if isStarting {
            startCancelled = true
            return true
        }
        if isRecording {
            stop()
            return true
        }
        return false
    }

    func stop() {
        guard let recorder = activeRecorder else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        closeHUD()
        activeRecorder = nil
        onStateChange?()
        let format = activeFormat
        let target = transcodeTarget
        Task {
            do {
                var url = try await recorder.stop()
                if let target {
                    let settings = TaskSettings.load()
                    Notifier.notify(title: "Converting to \(target.displayName)…", body: url.lastPathComponent)
                    let converted = url.deletingPathExtension().appendingPathExtension(target.fileExtension)
                    do {
                        try await FFmpeg.transcode(
                            input: url, output: converted, format: target,
                            customArgs: settings.screenRecordCustomFFmpegArgs,
                            twoPass: settings.screenRecordTwoPassEncoding
                        )
                        try? FileManager.default.removeItem(at: url)
                        url = converted
                    } catch {
                        // keep the MP4 so the recording isn't lost
                        Notifier.notify(title: "\(target.displayName) conversion failed — kept MP4",
                                        body: error.localizedDescription)
                    }
                }
                finish(url: url, format: format)
            } catch {
                Notifier.notify(title: "Recording failed", body: error.localizedDescription)
            }
        }
    }

    func abort() {
        if isStarting {
            startCancelled = true
            return
        }
        guard let recorder = activeRecorder else { return }
        autoStopTask?.cancel()
        autoStopTask = nil
        closeHUD()
        activeRecorder = nil
        onStateChange?()
        Task { await recorder.abort() }
    }

    /// Abort with the optional C# ScreenRecordAskConfirmationOnAbort dialog.
    /// Recording continues while the dialog is up; countdowns cancel silently.
    func confirmAbort() {
        if isStarting {
            startCancelled = true
            return
        }
        guard isRecording else { return }
        if TaskSettings.load().screenRecordAskConfirmationOnAbort {
            let alert = NSAlert()
            alert.messageText = "Abort recording?"
            alert.informativeText = "The recording will be discarded."
            alert.addButton(withTitle: "Abort")
            alert.addButton(withTitle: "Keep Recording")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        abort()
    }

    private func begin(target: ScreenRecorder.Target, gif: Bool) async {
        let settings = TaskSettings.load()
        let config = ApplicationConfig.load()
        let codec = settings.screenRecordCodec.uppercased()
        var transcode = FFmpeg.TranscodeFormat(rawValue: codec)
        if transcode != nil, FFmpeg.installedPath == nil {
            Notifier.notify(title: "ffmpeg not found — recording H.264 instead",
                            body: "Install ffmpeg from SwiftX Settings to enable WebM/WebP/APNG.")
            transcode = nil
        }
        let format: RecordingFormat = gif ? .gif : .movie(hevc: codec == "HEVC")
        let fps = gif ? settings.gifFPS : settings.screenRecordFPS
        let url = SavePath.screenshotURL(config: config, task: settings, fileExtension: format.fileExtension)

        // HUD first: its windows must exist to be excluded from the stream
        let hud = RecordingHUD()
        hud.onPause = { [weak self] in self?.togglePause() }
        hud.onStop = { [weak self] in self?.stop() }
        hud.onAbort = { [weak self] in self?.confirmAbort() }
        if let screen = hudScreen(for: target) {
            hud.show(around: hudRect(for: target), on: screen)
        }
        self.hud = hud
        isStarting = true
        startCancelled = false
        defer { isStarting = false }

        let countdown = Int(settings.screenRecordStartDelay.rounded(.up))
        for remaining in stride(from: countdown, through: 1, by: -1) {
            hud.setCountdown(remaining)
            try? await Task.sleep(for: .seconds(1))
            if startCancelled {
                closeHUD()
                return
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let recorder = try await ScreenRecorder.start(
                target: target, format: format, fps: fps, outputURL: url,
                showsCursor: settings.screenRecordShowCursor,
                systemAudio: settings.screenRecordSystemAudio,
                microphone: settings.screenRecordMicrophone,
                excludingWindowIDs: hud.windowIDs
            )
            if startCancelled {
                // a toggle landed while the stream was spinning up
                closeHUD()
                Task { await recorder.abort() }
                return
            }
            activeRecorder = recorder
            activeFormat = format
            transcodeTarget = gif ? nil : transcode
            hud.beginRecording()
            if settings.screenRecordFixedDuration, settings.screenRecordDuration > 0 {
                autoStopTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(settings.screenRecordDuration))
                    guard !Task.isCancelled else { return }
                    self?.stop()
                }
            }
            onStateChange?()
        } catch {
            closeHUD()
            let alert = NSAlert()
            alert.messageText = "Recording failed"
            alert.informativeText = error.localizedDescription
                + "\n\nIf this is a permission problem, grant Screen Recording access in SwiftX Settings."
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// The rect the border frame surrounds; window recordings have no fixed
    /// rect (the stream follows the window), so they get no frame.
    private func hudRect(for target: ScreenRecorder.Target) -> NSRect? {
        switch target {
        case .region(let rect): return rect
        case .display(let screen): return screen.frame
        case .frontmostWindow: return nil
        }
    }

    private func hudScreen(for target: ScreenRecorder.Target) -> NSScreen? {
        switch target {
        case .display(let screen):
            return screen
        case .region(let rect):
            func overlap(_ screen: NSScreen) -> CGFloat {
                let part = screen.frame.intersection(rect)
                return part.isNull ? 0 : part.width * part.height
            }
            return NSScreen.screens.max { overlap($0) < overlap($1) } ?? NSScreen.main
        case .frontmostWindow:
            return NSScreen.main
        }
    }

    private func closeHUD() {
        hud?.close()
        hud = nil
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
