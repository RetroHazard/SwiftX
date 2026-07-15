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
