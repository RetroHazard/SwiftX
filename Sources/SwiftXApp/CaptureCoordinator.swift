// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Runs captures and hands each result to AfterCapturePipeline, which applies
// the configured after-capture task chain.

import AppKit
import CaptureKit
import SharedKit

@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// Most recent region selection, for LastRegion capture. In-memory only,
    /// like the Windows app within a session.
    private var lastRegion: RegionSelection?

    func captureRegion() {
        Task {
            await applyScreenshotDelay()
            guard let selection = await RegionSelectController().selectRegionDetailed() else { return }
            lastRegion = selection
            // let the compositor remove the overlay before shooting
            try? await Task.sleep(for: .milliseconds(80))
            await run(isRegionCapture: true) {
                selection.applyMask(to: try await ScreenCapture.captureRegion(
                    cocoaRect: selection.rect, showsCursor: TaskSettings.load().showCursor))
            }
        }
    }

    /// Re-captures the previous region; falls back to the picker the first time.
    func captureLastRegion() {
        guard let selection = lastRegion else { return captureRegion() }
        Task {
            await applyScreenshotDelay()
            await run(isRegionCapture: true) {
                selection.applyMask(to: try await ScreenCapture.captureRegion(
                    cocoaRect: selection.rect, showsCursor: TaskSettings.load().showCursor))
            }
        }
    }

    func captureFullScreen() {
        Task {
            await applyScreenshotDelay()
            await run { try await ScreenCapture.captureDisplay(showsCursor: TaskSettings.load().showCursor) }
        }
    }

    func captureActiveWindow() {
        // sample the frontmost app before any of our UI can steal focus
        var app = NSWorkspace.shared.frontmostApplication
        Task {
            if await applyScreenshotDelay() {
                // the delay exists to let the user set a window up; resample
                app = NSWorkspace.shared.frontmostApplication
            }
            await run(processName: app?.localizedName) {
                try await ScreenCapture.captureFrontmostWindow(
                    processID: app?.processIdentifier, showsCursor: TaskSettings.load().showCursor)
            }
        }
    }

    /// Captures the stored CaptureCustomRegion rect without a picker.
    /// ponytail: an empty rect prompts a one-time region select and persists
    /// it; C# edits the rect in the task settings UI instead
    func captureCustomRegion() {
        Task {
            await applyScreenshotDelay()
            var settings = TaskSettings.load()
            if CSharpRect.parse(settings.captureCustomRegion) == nil {
                guard let selection = await RegionSelectController().selectRegionDetailed() else { return }
                settings.captureCustomRegion = CSharpRect.string(from: selection.rect)
                try? settings.save()
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let rect = CSharpRect.parse(settings.captureCustomRegion) else { return }
            let showCursor = settings.showCursor
            await run(isRegionCapture: true) {
                try await ScreenCapture.captureRegion(cocoaRect: rect, showsCursor: showCursor)
            }
        }
    }

    /// Captures the first window whose title or app name contains
    /// CaptureCustomWindow (C# CaptureCustomWindow).
    func captureCustomWindow() {
        let needle = TaskSettings.load().captureCustomWindow
        guard !needle.isEmpty else {
            Notifier.notify(title: L10n.t("notification.capture.custom_window_title"),
                            body: L10n.t("notification.capture.custom_window_unset"))
            return
        }
        let match = WindowLister.onScreenWindows(excludingPID: ProcessInfo.processInfo.processIdentifier)
            .first {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || $0.ownerName.localizedCaseInsensitiveContains(needle)
            }
        guard let match else {
            Notifier.notify(title: L10n.t("notification.capture.custom_window_title"),
                            body: L10n.t("notification.capture.custom_window_no_match", needle))
            return
        }
        captureWindow(match)
    }

    /// Captures one display picked from the menu.
    func captureScreen(_ screen: NSScreen) {
        Task {
            await applyScreenshotDelay()
            await run { try await ScreenCapture.captureDisplay(screen: screen,
                                                               showsCursor: TaskSettings.load().showCursor) }
        }
    }

    /// Captures one window picked from the menu.
    func captureWindow(_ window: CapturableWindow) {
        Task {
            await applyScreenshotDelay()
            await run(processName: window.ownerName, windowTitle: window.title) {
                try await ScreenCapture.captureWindow(windowID: window.id,
                                                      showsCursor: TaskSettings.load().showCursor)
            }
        }
    }

    /// C# ScreenshotDelay: wait before the capture job runs (including any
    /// region picker). Returns whether a delay actually happened.
    @discardableResult
    private func applyScreenshotDelay() async -> Bool {
        let delay = TaskSettings.load().screenshotDelay
        guard delay > 0 else { return false }
        try? await Task.sleep(for: .seconds(delay))
        return true
    }

    private func run(processName: String? = nil, windowTitle: String? = nil,
                     isRegionCapture: Bool = false,
                     _ operation: () async throws -> CGImage) async {
        do {
            let image = try await operation()
            await AfterCapturePipeline.run(image: image, processName: processName, windowTitle: windowTitle,
                                           isRegionCapture: isRegionCapture)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.t("alert.capture.failed")
        alert.informativeText = L10n.t("alert.capture.failed_info", error.localizedDescription)
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
