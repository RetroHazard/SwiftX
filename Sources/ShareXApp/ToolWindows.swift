// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Windows for the Tools menu (C# MainForm Tools). Each tool is a small
// SwiftUI view hosted in a tracked NSWindow.

import AppKit
import CaptureKit
import SwiftUI
import ToolsKit

@MainActor
enum ToolWindows {
    private static var open: [NSWindow] = []

    static func present(title: String, resizable: Bool = false, content: some View) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        if !resizable { window.styleMask.remove(.resizable) }
        window.isReleasedWhenClosed = false
        open.append(window)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { note in
            Task { @MainActor in open.removeAll { $0 == note.object as? NSWindow } }
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Region select → screenshot, shared by OCR / QR scan / ruler flows.
    static func captureRegionImage() async -> CGImage? {
        guard let rect = await RegionSelectController().selectRegion() else { return nil }
        // let the compositor remove the overlay before shooting
        try? await Task.sleep(for: .milliseconds(80))
        return try? await ScreenCapture.captureRegion(cocoaRect: rect)
    }

    // MARK: - OCR

    static func runOCRFromRegion() {
        Task {
            guard let image = await captureRegionImage() else { return }
            await showOCRResult(for: image)
        }
    }

    static func showOCRResult(for image: CGImage) async {
        do {
            let text = try await OCRService.recognizeText(in: image)
            present(title: "OCR", resizable: true, content: TextResultView(text: text))
        } catch {
            Notifier.notify(title: "OCR failed", body: error.localizedDescription)
        }
    }

    // MARK: - Image metadata

    static func showMetadataViewer() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        present(title: "Metadata — \(url.lastPathComponent)", resizable: true,
                content: MetadataView(url: url))
    }

    static func stripMetadataFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "The selected image will be rewritten without metadata."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageMetadata.strip(url: url)
            Notifier.notify(title: "Metadata stripped", body: url.lastPathComponent)
        } catch {
            Notifier.notify(title: "Strip metadata failed", body: error.localizedDescription)
        }
    }

    // MARK: - Hash checker

    static func showHashChecker() {
        present(title: "Hash Checker", content: HashCheckerView())
    }

    // MARK: - QR code

    static func showQRCode() {
        present(title: "QR Code", content: QRCodeToolView())
    }

    static func scanQRFromRegion() {
        Task {
            guard let image = await captureRegionImage() else { return }
            showQRDecodeResult(for: image)
        }
    }

    static func scanQRFromScreen() {
        Task {
            guard let image = try? await ScreenCapture.captureDisplay() else { return }
            showQRDecodeResult(for: image)
        }
    }

    static func showQRDecodeResult(for image: CGImage) {
        let payloads = (try? QRCodeTool.decode(image)) ?? []
        guard !payloads.isEmpty else {
            Notifier.notify(title: "QR code", body: "No QR code found.")
            return
        }
        present(title: "QR Code — Decoded", resizable: true,
                content: TextResultView(text: payloads.joined(separator: "\n")))
    }

    // MARK: - Color picker

    static func showColorPicker() {
        present(title: "Color Picker", content: ColorPickerToolView())
    }

    /// C# ScreenColorPicker: pick a pixel, copy it. NSColorSampler is the
    /// native magnifier loupe and needs no screen-recording permission.
    static func pickScreenColor() {
        NSColorSampler().show { picked in
            Task { @MainActor in
                guard let rgb = picked?.rgb255 else { return }
                let hex = ColorFormatter.hex(r: rgb.r, g: rgb.g, b: rgb.b)
                copyToClipboard(hex)
                Notifier.notify(title: "Screen color picker",
                                body: "\(hex) — RGB \(ColorFormatter.rgb(r: rgb.r, g: rgb.g, b: rgb.b)) copied")
            }
        }
    }
}

extension NSColor {
    /// sRGB components scaled to 0...255, the range every ColorFormatter takes.
    var rgb255: (r: Int, g: Int, b: Int)? {
        guard let srgb = usingColorSpace(.sRGB) else { return nil }
        return (Int((srgb.redComponent * 255).rounded()),
                Int((srgb.greenComponent * 255).rounded()),
                Int((srgb.blueComponent * 255).rounded()))
    }
}

private struct MetadataView: View {
    let url: URL
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 520, minHeight: 300)
            HStack {
                Button("Strip Metadata") {
                    do {
                        try ImageMetadata.strip(url: url)
                        reload()
                        Notifier.notify(title: "Metadata stripped", body: url.lastPathComponent)
                    } catch {
                        text = error.localizedDescription
                    }
                }
                Spacer()
                Button("Copy All") { ToolWindows.copyToClipboard(text) }
            }
        }
        .padding()
        .onAppear { reload() }
    }

    private func reload() {
        text = (try? ImageMetadata.describe(url: url)) ?? "Could not read metadata."
    }
}

private struct HashCheckerView: View {
    @State private var fileURL: URL?
    @State private var algorithm: HashAlgorithm = .sha256
    @State private var result = ""
    @State private var target = ""
    @State private var isHashing = false

    private var matches: Bool? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !result.isEmpty else { return nil }
        return trimmed.caseInsensitiveCompare(result) == .orderedSame
    }

    var body: some View {
        Form {
            LabeledContent("File") {
                HStack {
                    Text(fileURL?.lastPathComponent ?? "No file selected")
                        .foregroundStyle(fileURL == nil ? .secondary : .primary)
                        .truncationMode(.middle).lineLimit(1)
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        if panel.runModal() == .OK, let url = panel.url {
                            fileURL = url
                            rehash()
                        }
                    }
                }
            }
            Picker("Algorithm", selection: $algorithm) {
                ForEach(HashAlgorithm.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: algorithm) { rehash() }
            LabeledContent("Result") {
                HStack {
                    if isHashing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(result).monospaced().textSelection(.enabled)
                            .truncationMode(.middle).lineLimit(1)
                        if !result.isEmpty {
                            Button {
                                ToolWindows.copyToClipboard(result)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            TextField("Target (paste to compare)", text: $target)
                .monospaced()
            if let matches {
                Label(matches ? "Hashes match" : "Hashes do not match",
                      systemImage: matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(matches ? .green : .red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    fileURL = url
                    rehash()
                }
            }
            return true
        }
    }

    private func rehash() {
        guard let fileURL else { return }
        isHashing = true
        result = ""
        let algorithm = algorithm
        Task.detached(priority: .userInitiated) {
            let digest = (try? HashChecker.hashFile(at: fileURL, algorithm: algorithm)) ?? "Could not read file"
            await MainActor.run {
                result = digest
                isHashing = false
            }
        }
    }
}

private struct QRCodeToolView: View {
    @State private var text = "https://getsharex.com"

    var body: some View {
        VStack(spacing: 12) {
            TextField("Content", text: $text)
                .textFieldStyle(.roundedBorder)
            Group {
                if let code = QRCodeTool.generate(text) {
                    Image(code, scale: 2, label: Text("QR code"))
                        .resizable()
                        .interpolation(.none)
                } else {
                    Text("Enter content to encode").foregroundStyle(.secondary)
                }
            }
            .frame(width: 256, height: 256)
            HStack {
                Button("Copy Image") {
                    guard let code = QRCodeTool.generate(text) else { return }
                    ImageWriter.copyToClipboard(code)
                }
                Button("Save…") {
                    guard let code = QRCodeTool.generate(text) else { return }
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = "qrcode.png"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? ImageWriter.writePNG(code, to: url)
                    }
                }
                Spacer()
                Button("Decode File…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    if panel.runModal() == .OK, let url = panel.url,
                       let image = ImageLoader.load(url: url) {
                        ToolWindows.showQRDecodeResult(for: image)
                    }
                }
                Button("Scan Region…") { ToolWindows.scanQRFromRegion() }
            }
        }
        .padding()
        .frame(width: 420)
        .fixedSize()
    }
}

/// Selectable text + copy, used by OCR and QR decode results.
struct TextResultView: View {
    @State var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .frame(minWidth: 420, minHeight: 220)
            HStack {
                Text("\(text.count) characters").foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("Copy All") { ToolWindows.copyToClipboard(text) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        .padding()
    }
}

private struct ColorPickerToolView: View {
    @State private var color = Color.red

    var body: some View {
        Form {
            ColorPicker("Color", selection: $color, supportsOpacity: false)
            Button("Pick from Screen…") {
                NSColorSampler().show { picked in
                    if let picked { color = Color(nsColor: picked) }
                }
            }
            Section("Copy as") {
                let rgb = NSColor(color).rgb255 ?? (0, 0, 0)
                copyRow("Hex", ColorFormatter.hex(r: rgb.r, g: rgb.g, b: rgb.b))
                copyRow("RGB", ColorFormatter.rgb(r: rgb.r, g: rgb.g, b: rgb.b))
                copyRow("HSB", ColorFormatter.hsb(r: rgb.r, g: rgb.g, b: rgb.b))
                copyRow("CMYK", ColorFormatter.cmyk(r: rgb.r, g: rgb.g, b: rgb.b))
                copyRow("Decimal", String(ColorFormatter.decimal(r: rgb.r, g: rgb.g, b: rgb.b)))
            }
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize()
    }

    private func copyRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            HStack {
                Text(value).textSelection(.enabled).monospaced()
                Button {
                    ToolWindows.copyToClipboard(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(label)")
            }
        }
    }
}
