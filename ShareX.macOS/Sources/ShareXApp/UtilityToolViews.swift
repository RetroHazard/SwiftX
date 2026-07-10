// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Utility tool windows: folder indexer, clipboard viewer, monitor test and
// window inspector (C# DirectoryIndexerForm / ClipboardViewerForm /
// MonitorTestForm / InspectWindowForm).

import AppKit
import SwiftUI
import ToolsKit
import UniformTypeIdentifiers

extension ToolWindows {
    static func showFolderIndexer() {
        present(title: "Index Folder", content: FolderIndexerView())
    }

    static func showClipboardViewer() {
        present(title: "Clipboard Viewer", resizable: true, content: ClipboardViewerView())
    }

    static func showWindowInspector() {
        present(title: "Inspect Window", content: InspectWindowView())
    }

    static func showMonitorTest() {
        guard let screen = NSScreen.main else { return }
        let window = MonitorTestWindow(contentRect: screen.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
        let model = MonitorTestModel()
        window.level = .screenSaver
        window.contentView = NSHostingView(rootView: MonitorTestView(model: model))
        window.onAction = { [weak window] action in
            switch action {
            case .close: window?.close()
            case .previous: model.index = (model.index - 1 + MonitorTestView.patterns.count)
                % MonitorTestView.patterns.count
            case .next: model.index = (model.index + 1) % MonitorTestView.patterns.count
            }
        }
        track(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Folder indexer

private struct FolderIndexerView: View {
    @State private var folder: URL?
    @State private var options = IndexerOptions()

    var body: some View {
        Form {
            LabeledContent("Folder") {
                HStack {
                    Text(folder?.lastPathComponent ?? "No folder selected")
                        .foregroundStyle(folder == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button("Browse…") {
                        folder = ToolWindows.folderPanel(message: "Choose the folder to index")
                    }
                }
            }
            Picker("Format", selection: $options.format) {
                ForEach(IndexerOptions.Format.allCases, id: \.self) { Text($0.rawValue) }
            }
            Toggle("Skip hidden files", isOn: $options.skipHidden)
            Toggle("Show sizes", isOn: $options.showSizes)
            Stepper(options.maxDepth == 0 ? "Depth: unlimited" : "Depth: \(options.maxDepth)",
                    value: $options.maxDepth, in: 0...20)
            HStack {
                Spacer()
                Button("Generate…") { generate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(folder == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }

    private func generate() {
        guard let folder else { return }
        let ext = options.format == .html ? "html" : "txt"
        guard let output = ToolWindows.savePanel(suggestedName: "\(folder.lastPathComponent)-index.\(ext)")
        else { return }
        do {
            let index = try FolderIndexer.index(folder: folder, options: options)
            try index.write(to: output, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([output])
        } catch {
            Notifier.notify(title: "Index folder failed", body: error.localizedDescription)
        }
    }
}

// MARK: - Clipboard viewer

private struct ClipboardViewerView: View {
    @State private var types: [NSPasteboard.PasteboardType] = []
    @State private var selected: NSPasteboard.PasteboardType?

    var body: some View {
        HSplitView {
            List(types, id: \.rawValue, selection: $selected) { type in
                Text(type.rawValue).lineLimit(1).truncationMode(.middle).tag(type)
            }
            .frame(minWidth: 220, maxWidth: 320)
            preview
                .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 560, minHeight: 300)
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
        }
        .onAppear { refresh() }
    }

    @ViewBuilder
    private var preview: some View {
        if let selected, let data = NSPasteboard.general.data(forType: selected) {
            if let image = NSImage(data: data), image.size.width > 0 {
                Image(nsImage: image).resizable().scaledToFit().padding()
            } else if let text = String(data: data, encoding: .utf8) {
                ScrollView {
                    Text(text).font(.body.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else {
                Text("\(data.count) bytes of binary data").foregroundStyle(.secondary)
            }
        } else {
            Text("Select a clipboard format").foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        types = NSPasteboard.general.types ?? []
        selected = types.first
    }
}

// MARK: - Monitor test

@MainActor
final class MonitorTestModel: ObservableObject {
    @Published var index = 0
}

/// Borderless fullscreen window that still receives keys.
final class MonitorTestWindow: NSWindow {
    enum Action { case close, previous, next }
    var onAction: ((Action) -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onAction?(.close)      // Esc
        case 123: onAction?(.previous)  // ←
        default: onAction?(.next)       // → / space / anything else
        }
    }

    override func mouseDown(with event: NSEvent) {
        onAction?(.next)
    }
}

struct MonitorTestView: View {
    static let patterns: [(name: String, style: AnyShapeStyle)] = [
        ("White", AnyShapeStyle(Color.white)),
        ("Black", AnyShapeStyle(Color.black)),
        ("Red", AnyShapeStyle(Color(red: 1, green: 0, blue: 0))),
        ("Green", AnyShapeStyle(Color(red: 0, green: 1, blue: 0))),
        ("Blue", AnyShapeStyle(Color(red: 0, green: 0, blue: 1))),
        ("Grayscale gradient", AnyShapeStyle(
            LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing))),
        ("Color gradient", AnyShapeStyle(
            LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple],
                           startPoint: .leading, endPoint: .trailing)))
    ]

    @ObservedObject var model: MonitorTestModel

    var body: some View {
        Rectangle()
            .fill(Self.patterns[model.index].style)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("\(Self.patterns[model.index].name) — arrows or click to cycle, Esc to exit")
                    .font(.callout)
                    .padding(8)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 40)
            }
    }
}

// MARK: - Window inspector

private struct WindowEntry: Identifiable, Hashable {
    let id: UInt32
    let title: String
    let app: String
    let pid: Int32
    let bounds: CGRect
    let layer: Int
    let alpha: Double

    var label: String { title.isEmpty ? app : "\(app) — \(title)" }
}

private struct InspectWindowView: View {
    @State private var windows: [WindowEntry] = []
    @State private var selectedID: UInt32?

    private var selected: WindowEntry? { windows.first { $0.id == selectedID } }

    var body: some View {
        Form {
            HStack {
                Picker("Window", selection: $selectedID) {
                    ForEach(windows) { entry in
                        Text(entry.label).lineLimit(1).tag(Optional(entry.id))
                    }
                }
                Button("Refresh", systemImage: "arrow.clockwise") { refresh() }
                    .labelStyle(.iconOnly)
            }
            if let entry = selected {
                LabeledContent("Title", value: entry.title.isEmpty ? "—" : entry.title)
                LabeledContent("Application", value: entry.app)
                LabeledContent("Process ID", value: String(entry.pid))
                LabeledContent("Window ID", value: String(entry.id))
                LabeledContent("Position", value: String(format: "%.0f, %.0f",
                                                         entry.bounds.origin.x, entry.bounds.origin.y))
                LabeledContent("Size", value: String(format: "%.0f × %.0f",
                                                     entry.bounds.width, entry.bounds.height))
                LabeledContent("Layer", value: String(entry.layer))
                LabeledContent("Opacity", value: String(format: "%.0f%%", entry.alpha * 100))
                HStack {
                    Spacer()
                    Button("Copy Info") {
                        ToolWindows.copyToClipboard("""
                        Title: \(entry.title)
                        Application: \(entry.app) (pid \(entry.pid))
                        Window ID: \(entry.id)
                        Bounds: \(Int(entry.bounds.origin.x)), \(Int(entry.bounds.origin.y)), \
                        \(Int(entry.bounds.width)) × \(Int(entry.bounds.height))
                        Layer: \(entry.layer), Opacity: \(Int(entry.alpha * 100))%
                        """)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { refresh() }
    }

    private func refresh() {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }
        windows = info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? UInt32,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = dict[kCGWindowBounds as String] as CFTypeRef?,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary),
                  bounds.width > 1, bounds.height > 1
            else { return nil }
            return WindowEntry(
                id: id,
                title: dict[kCGWindowName as String] as? String ?? "",
                app: dict[kCGWindowOwnerName as String] as? String ?? "?",
                pid: pid,
                bounds: bounds,
                layer: dict[kCGWindowLayer as String] as? Int ?? 0,
                alpha: dict[kCGWindowAlpha as String] as? Double ?? 1
            )
        }
        if selected == nil { selectedID = windows.first?.id }
    }
}
