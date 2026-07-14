// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Runs captures and applies the after-capture behavior. Until the task
// pipeline lands (Phase 2), behavior is fixed: copy to clipboard + save to file.

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
            guard let selection = await RegionSelectController().selectRegionDetailed() else { return }
            lastRegion = selection
            // let the compositor remove the overlay before shooting
            try? await Task.sleep(for: .milliseconds(80))
            await run { selection.applyMask(to: try await ScreenCapture.captureRegion(cocoaRect: selection.rect)) }
        }
    }

    /// Re-captures the previous region; falls back to the picker the first time.
    func captureLastRegion() {
        guard let selection = lastRegion else { return captureRegion() }
        Task {
            await run { selection.applyMask(to: try await ScreenCapture.captureRegion(cocoaRect: selection.rect)) }
        }
    }

    func captureFullScreen() {
        Task {
            await run { try await ScreenCapture.captureDisplay() }
        }
    }

    func captureActiveWindow() {
        // sample the frontmost app before any of our UI can steal focus
        let app = NSWorkspace.shared.frontmostApplication
        Task {
            await run(processName: app?.localizedName) {
                try await ScreenCapture.captureFrontmostWindow(processID: app?.processIdentifier)
            }
        }
    }

    /// Captures the stored CaptureCustomRegion rect without a picker.
    /// ponytail: an empty rect prompts a one-time region select and persists
    /// it; C# edits the rect in the task settings UI instead
    func captureCustomRegion() {
        Task {
            var settings = TaskSettings.load()
            if CSharpRect.parse(settings.captureCustomRegion) == nil {
                guard let selection = await RegionSelectController().selectRegionDetailed() else { return }
                settings.captureCustomRegion = CSharpRect.string(from: selection.rect)
                try? settings.save()
                try? await Task.sleep(for: .milliseconds(80))
            }
            guard let rect = CSharpRect.parse(settings.captureCustomRegion) else { return }
            await run { try await ScreenCapture.captureRegion(cocoaRect: rect) }
        }
    }

    /// Captures the first window whose title or app name contains
    /// CaptureCustomWindow (C# CaptureCustomWindow).
    func captureCustomWindow() {
        let needle = TaskSettings.load().captureCustomWindow
        guard !needle.isEmpty else {
            Notifier.notify(title: "Custom window capture",
                            body: "Set CaptureCustomWindow in TaskSettings.json first.")
            return
        }
        let match = WindowLister.onScreenWindows(excludingPID: ProcessInfo.processInfo.processIdentifier)
            .first {
                $0.title.localizedCaseInsensitiveContains(needle)
                    || $0.ownerName.localizedCaseInsensitiveContains(needle)
            }
        guard let match else {
            Notifier.notify(title: "Custom window capture", body: "No window matching \"\(needle)\".")
            return
        }
        captureWindow(match)
    }

    /// Captures one display picked from the menu.
    func captureScreen(_ screen: NSScreen) {
        Task {
            await run { try await ScreenCapture.captureDisplay(screen: screen) }
        }
    }

    /// Captures one window picked from the menu.
    func captureWindow(_ window: CapturableWindow) {
        Task {
            await run(processName: window.ownerName, windowTitle: window.title) {
                try await ScreenCapture.captureWindow(windowID: window.id)
            }
        }
    }

    private func run(processName: String? = nil, windowTitle: String? = nil,
                     _ operation: () async throws -> CGImage) async {
        do {
            let image = try await operation()
            await AfterCapturePipeline.run(image: image, processName: processName, windowTitle: windowTitle)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
            + "\n\nIf this is a permission problem, grant Screen Recording access in SwiftX Settings."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
