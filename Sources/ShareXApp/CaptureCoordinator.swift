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

    func captureRegion() {
        Task {
            guard let rect = await RegionSelectController().selectRegion() else { return }
            // let the compositor remove the overlay before shooting
            try? await Task.sleep(for: .milliseconds(80))
            await run { try await ScreenCapture.captureRegion(cocoaRect: rect) }
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

    private func run(processName: String? = nil, _ operation: () async throws -> CGImage) async {
        do {
            let image = try await operation()
            await AfterCapturePipeline.run(image: image, processName: processName)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
            + "\n\nIf this is a permission problem, grant Screen Recording access in ShareX Settings."
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
