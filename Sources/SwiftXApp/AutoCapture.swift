// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Repeating region capture (C# AutoCaptureForm). Each shot runs the normal
// after-capture pipeline with the interactive steps stripped (annotate, quick
// task menu, after-capture window) and sounds/banners suppressed.

import AppKit
import CaptureKit
import SharedKit
import SwiftUI

@MainActor
final class AutoCaptureController: ObservableObject {
    static let shared = AutoCaptureController()

    @Published private(set) var isRunning = false
    @Published private(set) var secondsLeft: Double = 0
    @Published private(set) var captureCount = 0

    private var loop: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        let config = ApplicationConfig.load()
        guard let region = CSharpRect.parse(config.autoCaptureRegion), !region.isEmpty else { return }
        isRunning = true
        captureCount = 0
        loop = Task { await run(region: region, config: config) }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        secondsLeft = 0
    }

    func toggle() { isRunning ? stop() : start() }

    private func run(region: CGRect, config: ApplicationConfig) async {
        while !Task.isCancelled {
            // C# WaitAfterUpload: hold the shot while uploads are in flight
            while config.autoCaptureWaitUpload, UploadTaskCenter.shared.isBusy, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
            if Task.isCancelled { break }
            if let image = try? await ScreenCapture.captureRegion(cocoaRect: region) {
                captureCount += 1
                var settings = TaskSettings.load()
                settings.afterCaptureJob.subtract([.annotateImage, .showQuickTaskMenu, .showAfterCaptureWindow])
                settings.playSoundAfterCapture = false
                await AfterCapturePipeline.run(image: image, settings: settings, quiet: true)
            }
            // 250ms ticks so the window's countdown stays live (C# timer)
            secondsLeft = max(config.autoCaptureRepeatTime, 1)
            while secondsLeft > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                secondsLeft -= 0.25
            }
        }
    }

    static func show() {
        ToolWindows.present(title: L10n.t("capture.auto.window_title"), content: AutoCaptureView())
    }
}

struct AutoCaptureView: View {
    @ObservedObject private var controller = AutoCaptureController.shared
    @State private var config = ApplicationConfig.load()

    var body: some View {
        Form {
            LabeledContent(L10n.t("capture.auto.region")) {
                Text(config.autoCaptureRegion.isEmpty ? L10n.t("capture.auto.not_set") : config.autoCaptureRegion)
                    .foregroundStyle(config.autoCaptureRegion.isEmpty ? .secondary : .primary)
            }
            HStack {
                Button(L10n.t("capture.auto.select_region")) {
                    Task {
                        guard let rect = await RegionSelectController().selectRegion() else { return }
                        setRegion(rect)
                    }
                }
                Button(L10n.t("capture.auto.full_screen")) {
                    if let frame = NSScreen.main?.frame { setRegion(frame) }
                }
            }
            .disabled(controller.isRunning)

            TextField(L10n.t("capture.auto.repeat_every"), value: $config.autoCaptureRepeatTime, format: .number)
                .frame(maxWidth: 220)
                .onChange(of: config.autoCaptureRepeatTime) { try? config.save() }
                .disabled(controller.isRunning)
            Toggle(L10n.t("capture.auto.wait_uploads"), isOn: $config.autoCaptureWaitUpload)
                .onChange(of: config.autoCaptureWaitUpload) { try? config.save() }
                .disabled(controller.isRunning)

            Divider()

            HStack {
                Button(controller.isRunning ? L10n.t("capture.auto.stop") : L10n.t("capture.auto.start")) {
                    controller.toggle()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!controller.isRunning && CSharpRect.parse(config.autoCaptureRegion) == nil)
                if controller.isRunning {
                    Text(L10n.t("capture.auto.status",
                                Int(controller.secondsLeft.rounded()), controller.captureCount))
                        .foregroundStyle(.secondary)
                } else if controller.captureCount > 0 {
                    Text(L10n.t("capture.auto.captured", controller.captureCount))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func setRegion(_ rect: CGRect) {
        config.autoCaptureRegion = CSharpRect.string(from: rect)
        try? config.save()
    }
}
