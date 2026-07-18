// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Image tool windows: viewer, combiner, splitter, thumbnailer
// (C# ImageViewer / ImageCombinerForm / ImageSplitterForm / ImageThumbnailerForm).

import AppKit
import CaptureKit
import SwiftUI
import ToolsKit

extension ToolWindows {
    static func showImageViewer() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        present(title: "Image Viewer", resizable: true, content: ImageViewerView(files: panel.urls))
    }

    static func showImageCombiner() {
        present(title: "Image Combiner", resizable: true, content: ImageCombinerView())
    }

    static func showImageSplitter() {
        present(title: "Image Splitter", content: ImageSplitterView())
    }

    static func showImageThumbnailer() {
        present(title: "Image Thumbnailer", resizable: true, content: ImageThumbnailerView())
    }

    /// Upstream v21 background remover (Vision subject lifting here).
    static func showBackgroundRemover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        present(title: "Background Remover — \(url.lastPathComponent)", resizable: true,
                content: BackgroundRemoverView(source: image))
    }

    /// Upstream v21 image comparer (side-by-side / slider diff).
    static func showImageComparer() {
        present(title: "Image Comparer", resizable: true, content: ImageComparerView())
    }

    static func savePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func folderPanel(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = message
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct ImageViewerView: View {
    let files: [URL]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let image = NSImage(contentsOf: files[index]) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Text("Could not load \(files[index].lastPathComponent)")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 480, minHeight: 320)
            HStack {
                Button {
                    index = (index - 1 + files.count) % files.count
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                Text("\(files[index].lastPathComponent) (\(index + 1) of \(files.count))")
                    .font(.caption)
                Button {
                    index = (index + 1) % files.count
                } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
            .disabled(files.count < 2)
        }
        .padding()
    }
}

/// Shared add/remove file list for the batch image tools.
private struct FileListPicker: View {
    @Binding var files: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            List(files, id: \.self) { url in
                Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            }
            .frame(minHeight: 120)
            HStack {
                Button("Add Images…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        files.append(contentsOf: panel.urls)
                    }
                }
                Button("Clear") { files.removeAll() }.disabled(files.isEmpty)
                Spacer()
                Text("\(files.count) images").foregroundStyle(.secondary).font(.caption)
            }
        }
    }
}

private struct ImageCombinerView: View {
    @State private var files: [URL] = []
    // C# ImageCombinerOptions defaults: vertical, no spacing, no wrap
    @State private var orientation: ImageCombineOrientation = .vertical
    @State private var alignment: ImageCombineAlignment = .leadingOrTop
    @State private var spacing = 0
    @State private var wrapAfter = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileListPicker(files: $files)
            HStack {
                Picker("Orientation", selection: $orientation) {
                    ForEach(ImageCombineOrientation.allCases, id: \.self) { Text($0.rawValue) }
                }
                .fixedSize()
                Picker("Alignment", selection: $alignment) {
                    ForEach(ImageCombineAlignment.allCases, id: \.self) { Text($0.rawValue) }
                }
                .fixedSize()
            }
            HStack {
                Stepper("Spacing: \(spacing) px", value: $spacing, in: 0...100)
                Stepper("Wrap after: \(wrapAfter)", value: $wrapAfter, in: 0...50)
                    .help("0 = single row/column")
            }
            HStack {
                Spacer()
                Button("Combine & Save…") { combine() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(files.count < 2)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private func combine() {
        let images = files.compactMap { ImageLoader.load(url: $0) }
        guard images.count == files.count else {
            Notifier.notify(title: "Image combiner", body: "Some files could not be read.")
            return
        }
        guard let combined = ImageTools.combine(images, orientation: orientation,
                                                alignment: alignment, spacing: spacing,
                                                wrapAfter: wrapAfter),
              let url = ToolWindows.savePanel(suggestedName: "combined.png") else { return }
        do {
            try ImageWriter.writePNG(combined, to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Notifier.notify(title: "Image combiner", body: error.localizedDescription)
        }
    }
}

private struct ImageSplitterView: View {
    @State private var file: URL?
    @State private var rows = 2
    @State private var columns = 2

    var body: some View {
        Form {
            LabeledContent("Image") {
                HStack {
                    Text(file?.lastPathComponent ?? "No file selected")
                        .foregroundStyle(file == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        if panel.runModal() == .OK { file = panel.url }
                    }
                }
            }
            Stepper("Rows: \(rows)", value: $rows, in: 1...20)
            Stepper("Columns: \(columns)", value: $columns, in: 1...20)
            HStack {
                Spacer()
                Button("Split & Save…") { split() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(file == nil || rows * columns < 2)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }

    private func split() {
        guard let file, let image = ImageLoader.load(url: file),
              let folder = ToolWindows.folderPanel(message: "Choose where to save the tiles") else { return }
        let tiles = ImageTools.split(image, rows: rows, columns: columns)
        guard !tiles.isEmpty else {
            Notifier.notify(title: "Image splitter", body: "The grid is larger than the image.")
            return
        }
        let base = file.deletingPathExtension().lastPathComponent
        do {
            // C# names tiles originalname1.png, originalname2.png, ...
            for (offset, tile) in tiles.enumerated() {
                try ImageWriter.writePNG(tile, to: folder.appendingPathComponent("\(base)\(offset + 1).png"))
            }
            NSWorkspace.shared.open(folder)
        } catch {
            Notifier.notify(title: "Image splitter", body: error.localizedDescription)
        }
    }
}

private struct ImageThumbnailerView: View {
    @State private var files: [URL] = []
    @State private var maxWidth = 256
    @State private var maxHeight = 256

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FileListPicker(files: $files)
            HStack {
                Stepper("Max width: \(maxWidth) px", value: $maxWidth, in: 16...2048, step: 16)
                Stepper("Max height: \(maxHeight) px", value: $maxHeight, in: 16...2048, step: 16)
            }
            HStack {
                Spacer()
                Button("Generate…") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(files.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 460)
    }

    private func generate() {
        guard let folder = ToolWindows.folderPanel(message: "Choose where to save the thumbnails") else { return }
        var written = 0
        for file in files {
            guard let image = ImageLoader.load(url: file),
                  let thumb = ImageWriter.thumbnail(image, width: maxWidth, height: maxHeight) else { continue }
            let name = file.deletingPathExtension().lastPathComponent + "_thumbnail.png"
            if (try? ImageWriter.writePNG(thumb, to: folder.appendingPathComponent(name))) != nil {
                written += 1
            }
        }
        Notifier.notify(title: "Image thumbnailer", body: "\(written) of \(files.count) thumbnails saved.")
        NSWorkspace.shared.open(folder)
    }
}

/// Upstream v21 background remover: preview on a checkerboard, Copy / Save.
private struct BackgroundRemoverView: View {
    let source: CGImage
    @State private var result: CGImage?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let result {
                    Image(decorative: result, scale: NSScreen.main?.backingScaleFactor ?? 2)
                        .resizable()
                        .scaledToFit()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else {
                    ProgressView("Isolating subject…")
                }
            }
            .frame(minWidth: 480, minHeight: 360, maxWidth: .infinity, maxHeight: .infinity)
            .background(CheckerboardBackground())

            HStack {
                Spacer()
                Button("Copy") {
                    if let result { ImageWriter.copyToClipboard(result) }
                }
                .disabled(result == nil)
                Button("Save As…") {
                    guard let result,
                          let url = ToolWindows.savePanel(suggestedName: "subject.png") else { return }
                    try? ImageWriter.writePNG(result, to: url)
                }
                .disabled(result == nil)
            }
        }
        .padding(12)
        .task {
            let source = source
            // Vision inference is slow; keep the window responsive
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try BackgroundRemover.removeBackground(from: source) }
            }.value
            switch outcome {
            case .success(let image): result = image
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
    }
}

/// Upstream v21 image comparer: side-by-side, or an overlay split by a slider.
private struct ImageComparerView: View {
    @State private var first: NSImage?
    @State private var second: NSImage?
    @State private var mode = "Slider"
    @State private var split = 0.5

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(first == nil ? "First Image…" : "First Image ✓") { pick { first = $0 } }
                Button(second == nil ? "Second Image…" : "Second Image ✓") { pick { second = $0 } }
                Spacer()
                Picker("", selection: $mode) {
                    Text("Slider").tag("Slider")
                    Text("Side by Side").tag("SideBySide")
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            if let first, let second {
                if mode == "SideBySide" {
                    HStack(spacing: 4) {
                        fitted(first)
                        Divider()
                        fitted(second)
                    }
                    .frame(minWidth: 640, minHeight: 400, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            fitted(first)
                            fitted(second)
                                .clipShape(LeadingSplit(fraction: split))
                            Rectangle()
                                .fill(Color.accentColor)
                                .frame(width: 2)
                                .offset(x: geo.size.width * split - 1)
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
                    .frame(minWidth: 640, minHeight: 400, maxWidth: .infinity, maxHeight: .infinity)
                    Slider(value: $split)
                }
            } else {
                Text("Choose two images to compare.")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 640, minHeight: 400, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }

    private func fitted(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pick(_ assign: @escaping (NSImage) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        assign(image)
    }
}

/// The left `fraction` of the rect; clips the top image in slider mode.
private struct LeadingSplit: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height))
    }
}
