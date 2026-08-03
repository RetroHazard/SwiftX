// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Video converter (ffmpeg) and video thumbnailer (AVFoundation) windows,
// mirroring C# VideoConverterForm / VideoThumbnailerForm.

import AppKit
import CaptureKit
import SharedKit
import SwiftUI
import ToolsKit
import UniformTypeIdentifiers

extension ToolWindows {
    static func showVideoConverter() {
        present(title: L10n.t("toolui.window.video_converter"), content: VideoConverterView())
    }

    static func showVideoThumbnailer() {
        present(title: L10n.t("toolui.window.video_thumbnailer"), content: VideoThumbnailerView())
    }

    static func openVideoPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct VideoConverterView: View {
    @State private var file: URL?
    @State private var codec: FFmpeg.ConvertCodec = .x264
    @State private var crf = 23
    @State private var bitrateKbps = 3000
    @State private var customArgs = ""
    @State private var isConverting = false

    var body: some View {
        Form {
            LabeledContent(L10n.t("toolui.video.video")) {
                HStack {
                    Text(file?.lastPathComponent ?? L10n.t("toolui.no_file_selected"))
                        .foregroundStyle(file == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button(L10n.t("common.browse")) { file = ToolWindows.openVideoPanel() }
                }
            }
            Picker(L10n.t("toolui.video.codec"), selection: $codec) {
                ForEach(FFmpeg.ConvertCodec.allCases, id: \.self) { Text($0.displayName) }
            }
            .onChange(of: codec) { crf = codec.defaultCRF }
            if codec.usesCRF {
                LabeledContent(L10n.t("toolui.video.quality_crf", crf)) {
                    Slider(value: Binding(get: { Double(crf) }, set: { crf = Int($0) }),
                           in: 0...51, step: 1)
                    .help(L10n.t("toolui.video.crf_help"))
                }
            }
            if codec.usesBitrate {
                TextField(L10n.t("toolui.video.bitrate"), value: $bitrateKbps, format: .number)
            }
            TextField(L10n.t("toolui.video.custom_args"), text: $customArgs)
                .font(.body.monospaced())
            if FFmpeg.installedPath == nil {
                Label(L10n.t("toolui.video.ffmpeg_missing"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                if isConverting {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.t("toolui.video.convert")) { convert() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(file == nil || isConverting || FFmpeg.installedPath == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func convert() {
        guard let file else { return }
        let suggested = file.deletingPathExtension().lastPathComponent + "." + codec.fileExtension
        guard let output = ToolWindows.savePanel(suggestedName: suggested) else { return }
        isConverting = true
        let (codec, crf, bitrate, custom) = (codec, crf, bitrateKbps, customArgs)
        Task {
            do {
                try await FFmpeg.convert(input: file, output: output, codec: codec,
                                         crf: crf, bitrateKbps: bitrate, customArgs: custom)
                Notifier.notify(title: L10n.t("toolui.video.converted_title"), body: output.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch {
                Notifier.notify(title: L10n.t("toolui.video.convert_failed_title"),
                                body: error.localizedDescription)
            }
            isConverting = false
        }
    }
}

private struct VideoThumbnailerView: View {
    @State private var file: URL?
    // C# VideoThumbnailOptions defaults
    @State private var count = 9
    @State private var columns = 3
    @State private var addTimestamp = true
    @State private var isWorking = false

    var body: some View {
        Form {
            LabeledContent(L10n.t("toolui.video.video")) {
                HStack {
                    Text(file?.lastPathComponent ?? L10n.t("toolui.no_file_selected"))
                        .foregroundStyle(file == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button(L10n.t("common.browse")) { file = ToolWindows.openVideoPanel() }
                }
            }
            Stepper(L10n.t("toolui.video.thumbnails_count", count), value: $count, in: 1...50)
            Stepper(L10n.t("toolui.video.thumb_columns", columns), value: $columns, in: 1...10)
            Toggle(L10n.t("toolui.video.add_timestamps"), isOn: $addTimestamp)
            HStack {
                Spacer()
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.t("toolui.generate")) { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(file == nil || isWorking)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func generate() {
        guard let file else { return }
        let suggested = file.deletingPathExtension().lastPathComponent + "_Thumbnail.png"
        guard let output = ToolWindows.savePanel(suggestedName: suggested) else { return }
        isWorking = true
        var options = VideoThumbnailOptions()
        options.count = count
        options.columns = columns
        options.addTimestamp = addTimestamp
        Task {
            do {
                let frames = try await VideoThumbnailer.frames(from: file, options: options)
                guard let sheet = VideoThumbnailer.contactSheet(frames, options: options) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try ImageWriter.writePNG(sheet, to: output)
                Notifier.notify(title: L10n.t("toolui.video.thumbs_saved_title"), body: output.lastPathComponent)
                NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch {
                Notifier.notify(title: L10n.t("toolui.video.thumbs_failed_title"),
                                body: error.localizedDescription)
            }
            isWorking = false
        }
    }
}
