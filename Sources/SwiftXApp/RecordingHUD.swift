// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Recording session HUD (the C# ScreenRecordForm chrome): a dashed border
// drawn around the recorded rect plus a floating control strip with the
// elapsed time and pause/stop/abort buttons. Both windows opt out of screen
// sharing (sharingType .none) and their IDs are also handed to the recorder
// for SCStream filter exclusion, so they never appear in the recording.

import AppKit
import SwiftUI

@MainActor
final class RecordingHUDModel: ObservableObject {
    enum Phase: Equatable {
        case countdown(Int)
        case recording
        case paused
    }

    @Published var phase: Phase = .countdown(0)
    @Published var elapsed: TimeInterval = 0

    var elapsedText: String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = total / 60 % 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

@MainActor
final class RecordingHUD {
    var onPause: (() -> Void)?
    var onStop: (() -> Void)?
    var onAbort: (() -> Void)?

    private let model = RecordingHUDModel()
    private var frameWindow: NSWindow?
    private var strip: NSPanel?
    private var timer: Timer?
    private var startedAt: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pausedAt: Date?

    private static let borderWidth: CGFloat = 3

    /// Window IDs the recorder excludes from the stream.
    var windowIDs: [CGWindowID] {
        [frameWindow, strip].compactMap { $0 }.map { CGWindowID($0.windowNumber) }
    }

    /// `rect` (Cocoa global) positions the border frame; nil (window
    /// recordings, where the recorded rect follows the window) shows only the
    /// control strip near the bottom of `screen`.
    func show(around rect: NSRect?, on screen: NSScreen) {
        if let rect {
            let window = NSWindow(
                contentRect: rect.insetBy(dx: -Self.borderWidth, dy: -Self.borderWidth),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.sharingType = .none
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = RecordingBorderView()
            window.orderFrontRegardless()
            frameWindow = window
        }

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.sharingType = .none
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: RecordingStripView(
            model: model,
            onPause: { [weak self] in self?.onPause?() },
            onStop: { [weak self] in self?.onStop?() },
            onAbort: { [weak self] in self?.onAbort?() }
        ))
        let size = panel.contentView?.fittingSize ?? NSSize(width: 220, height: 36)
        panel.setContentSize(size)
        panel.setFrameOrigin(stripOrigin(size: size, around: rect, on: screen))
        panel.orderFrontRegardless()
        strip = panel
    }

    /// Below the recorded rect when there is room, else just inside its
    /// bottom edge (full-display recordings); always clamped on screen.
    private func stripOrigin(size: NSSize, around rect: NSRect?, on screen: NSScreen) -> NSPoint {
        let target = rect ?? screen.visibleFrame
        var x = target.midX - size.width / 2
        var y = target.minY - size.height - 8
        if y < screen.visibleFrame.minY {
            y = target.minY + 8
        }
        x = max(screen.visibleFrame.minX, min(x, screen.visibleFrame.maxX - size.width))
        return NSPoint(x: x, y: y)
    }

    func setCountdown(_ remaining: Int) {
        model.phase = .countdown(remaining)
    }

    func beginRecording() {
        model.phase = .recording
        startedAt = Date()
        pausedAccumulated = 0
        pausedAt = nil
        model.elapsed = 0
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Mirrors the recorder's pause bookkeeping so the displayed elapsed time
    /// matches the output file's timeline (pause gaps are cut from both).
    func setPaused(_ paused: Bool) {
        guard startedAt != nil else { return }
        if paused, pausedAt == nil {
            pausedAt = Date()
        } else if !paused, let pausedAt {
            pausedAccumulated += Date().timeIntervalSince(pausedAt)
            self.pausedAt = nil
        }
        model.phase = paused ? .paused : .recording
    }

    private func tick() {
        guard let startedAt, pausedAt == nil else { return }
        model.elapsed = Date().timeIntervalSince(startedAt) - pausedAccumulated
    }

    func close() {
        timer?.invalidate()
        timer = nil
        frameWindow?.close()
        frameWindow = nil
        strip?.close()
        strip = nil
    }
}

/// The dashed border around the recorded area.
private final class RecordingBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 1.5, dy: 1.5))
        path.lineWidth = 3
        path.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}

private struct RecordingStripView: View {
    @ObservedObject var model: RecordingHUDModel
    let onPause: () -> Void
    let onStop: () -> Void
    let onAbort: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch model.phase {
            case .countdown(let remaining):
                Image(systemName: "record.circle")
                    .foregroundStyle(.secondary)
                Text("Recording in \(remaining)…")
                    .monospacedDigit()
                Button { onAbort() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Cancel")
            case .recording, .paused:
                Circle()
                    .fill(model.phase == .paused ? Color.secondary : Color.red)
                    .frame(width: 10, height: 10)
                Text(model.elapsedText)
                    .font(.body.monospacedDigit())
                Button { onPause() } label: {
                    Image(systemName: model.phase == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.borderless)
                .help(model.phase == .paused ? "Resume" : "Pause")
                Button { onStop() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.borderless)
                    .help("Stop and save")
                Button { onAbort() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Abort and discard")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .fixedSize()
    }
}
