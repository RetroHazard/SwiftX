// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Scrolling capture (C# ScrollingCaptureForm/Manager): select a region, then
// repeatedly shoot it while posting synthetic scroll-wheel events to the
// window underneath, stitching the frames until the content stops moving.

import AppKit
import CaptureKit
import SharedKit
import SwiftUI

@MainActor
final class ScrollingCaptureController: ObservableObject {
    static let shared = ScrollingCaptureController()

    @Published private(set) var isCapturing = false
    @Published private(set) var frameCount = 0

    private var stopRequested = false

    func start() {
        guard !isCapturing else { return }
        Task {
            guard let rect = await RegionSelectController().selectRegion() else { return }
            let options = TaskSettings.load().scrollingCapture
            isCapturing = true
            stopRequested = false
            frameCount = 0
            defer { isCapturing = false }

            // scroll-wheel events land on the window under the cursor, no
            // activation needed - just park the cursor inside the region
            warpCursor(toCocoaPoint: CGPoint(x: rect.midX, y: rect.midY))
            try? await Task.sleep(for: .milliseconds(options.startDelay))
            if options.autoScrollTop {
                postKeyPress(virtualKey: 115) // Home
                try? await Task.sleep(for: .milliseconds(options.scrollDelay))
            }

            var stitcher = ScrollingCaptureStitcher(autoIgnoreBottomEdge: options.autoIgnoreBottomEdge)
            var previous: ScrollingCaptureStitcher.Frame?
            while !stopRequested {
                guard let shot = try? await ScreenCapture.captureRegion(cocoaRect: rect),
                      let frame = ScrollingCaptureStitcher.Frame(shot) else { break }
                // content stopped moving = reached the bottom
                if frame == previous { break }
                postScrollWheel(linesDown: options.scrollAmount)
                let started = ContinuousClock.now
                guard stitcher.append(frame) else { break }
                frameCount += 1
                previous = frame
                let elapsed = started.duration(to: .now)
                let remaining = Duration.milliseconds(options.scrollDelay) - elapsed
                if remaining > .zero { try? await Task.sleep(for: remaining) }
            }

            if let image = stitcher.makeImage() {
                if stitcher.status == .partiallySuccessful {
                    Notifier.notify(title: L10n.t("capture.scrolling.window_title"),
                                    body: L10n.t("capture.scrolling.seams_warning"))
                }
                await AfterCapturePipeline.run(image: image)
            } else {
                Notifier.notify(title: L10n.t("capture.scrolling.window_title"),
                                body: L10n.t("capture.scrolling.stitch_failed"))
            }
        }
    }

    func stop() { stopRequested = true }

    private func warpCursor(toCocoaPoint point: CGPoint) {
        // CG event coordinates are top-left origin on the primary display
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: point.x, y: primaryMaxY - point.y))
    }

    private func postScrollWheel(linesDown: Int) {
        // negative wheel1 scrolls content down, like C#'s -120 * amount
        CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                wheel1: Int32(-linesDown), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func postKeyPress(virtualKey: CGKeyCode) {
        for keyDown in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: keyDown)?
                .post(tap: .cghidEventTap)
        }
    }

    static func show() {
        ToolWindows.present(title: L10n.t("capture.scrolling.window_title"), content: ScrollingCaptureView())
    }
}

struct ScrollingCaptureView: View {
    @ObservedObject private var controller = ScrollingCaptureController.shared
    @State private var options = TaskSettings.load().scrollingCapture

    var body: some View {
        Form {
            TextField(L10n.t("capture.scrolling.start_delay"), value: $options.startDelay, format: .number)
            TextField(L10n.t("capture.scrolling.scroll_delay"), value: $options.scrollDelay, format: .number)
            TextField(L10n.t("capture.scrolling.scroll_amount"), value: $options.scrollAmount, format: .number)
            Toggle(L10n.t("capture.scrolling.scroll_to_top"), isOn: $options.autoScrollTop)
            Toggle(L10n.t("capture.scrolling.ignore_bottom_edge"), isOn: $options.autoIgnoreBottomEdge)

            Divider()

            HStack {
                if controller.isCapturing {
                    Button(L10n.t("capture.scrolling.stop")) { controller.stop() }
                        .keyboardShortcut(.defaultAction)
                    Text(L10n.t("capture.scrolling.frames", controller.frameCount))
                        .foregroundStyle(.secondary)
                } else {
                    Button(L10n.t("capture.scrolling.select_start")) {
                        save()
                        controller.start()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onChange(of: options) { save() }
        .padding()
        .frame(width: 360)
    }

    private func save() {
        var settings = TaskSettings.load()
        settings.scrollingCapture = options
        try? settings.save()
    }
}
