// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Utility tool windows: folder indexer, clipboard viewer, monitor test and
// window inspector (C# DirectoryIndexerForm / ClipboardViewerForm /
// MonitorTestForm / InspectWindowForm).

import AppKit
import SharedKit
import SwiftUI
import ToolsKit
import UniformTypeIdentifiers

extension ToolWindows {
    static func showFolderIndexer() {
        present(title: L10n.t("toolui.window.index_folder"), content: FolderIndexerView())
    }

    static func showClipboardViewer() {
        present(title: L10n.t("toolui.window.clipboard_viewer"), resizable: true, content: ClipboardViewerView())
    }

    static func showWindowInspector() {
        present(title: L10n.t("toolui.window.inspect_window"), content: InspectWindowView())
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
            LabeledContent(L10n.t("toolui.indexer.folder")) {
                HStack {
                    Text(folder?.lastPathComponent ?? L10n.t("toolui.indexer.no_folder"))
                        .foregroundStyle(folder == nil ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Button(L10n.t("common.browse")) {
                        folder = ToolWindows.folderPanel(message: L10n.t("toolui.indexer.choose_folder"))
                    }
                }
            }
            Picker(L10n.t("toolui.indexer.format"), selection: $options.format) {
                ForEach(IndexerOptions.Format.allCases, id: \.self) { Text($0.localizedName) }
            }
            Toggle(L10n.t("toolui.indexer.skip_hidden"), isOn: $options.skipHidden)
            Toggle(L10n.t("toolui.indexer.show_sizes"), isOn: $options.showSizes)
            Stepper(options.maxDepth == 0 ? L10n.t("toolui.indexer.depth_unlimited")
                                          : L10n.t("toolui.indexer.depth", options.maxDepth),
                    value: $options.maxDepth, in: 0...20)
            HStack {
                Spacer()
                Button(L10n.t("toolui.generate")) { generate() }
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
            Notifier.notify(title: L10n.t("toolui.indexer.failed_title"), body: error.localizedDescription)
        }
    }
}

/// Display names for the indexer output formats; rawValues stay the
/// persisted/identity values.
extension IndexerOptions.Format {
    var localizedName: String {
        switch self {
        case .text: return L10n.t("toolui.indexer.format.text")
        case .html: return L10n.t("toolui.indexer.format.html")
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
            Button(L10n.t("toolui.refresh"), systemImage: "arrow.clockwise") { refresh() }
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
                Text(L10n.t("toolui.clipboard.binary", data.count)).foregroundStyle(.secondary)
            }
        } else {
            Text(L10n.t("toolui.clipboard.select_format")).foregroundStyle(.secondary)
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
        (L10n.t("toolui.monitor.pattern.white"), AnyShapeStyle(Color.white)),
        (L10n.t("toolui.monitor.pattern.black"), AnyShapeStyle(Color.black)),
        (L10n.t("toolui.monitor.pattern.red"), AnyShapeStyle(Color(red: 1, green: 0, blue: 0))),
        (L10n.t("toolui.monitor.pattern.green"), AnyShapeStyle(Color(red: 0, green: 1, blue: 0))),
        (L10n.t("toolui.monitor.pattern.blue"), AnyShapeStyle(Color(red: 0, green: 0, blue: 1))),
        (L10n.t("toolui.monitor.pattern.grayscale_gradient"), AnyShapeStyle(
            LinearGradient(colors: [.black, .white], startPoint: .leading, endPoint: .trailing))),
        (L10n.t("toolui.monitor.pattern.color_gradient"), AnyShapeStyle(
            LinearGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple],
                           startPoint: .leading, endPoint: .trailing)))
    ]

    @ObservedObject var model: MonitorTestModel

    var body: some View {
        Rectangle()
            .fill(Self.patterns[model.index].style)
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text(L10n.t("toolui.monitor.hint", Self.patterns[model.index].name))
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
                Picker(L10n.t("toolui.inspect.window"), selection: $selectedID) {
                    ForEach(windows) { entry in
                        Text(entry.label).lineLimit(1).tag(Optional(entry.id))
                    }
                }
                Button(L10n.t("toolui.refresh"), systemImage: "arrow.clockwise") { refresh() }
                    .labelStyle(.iconOnly)
            }
            if let entry = selected {
                LabeledContent(L10n.t("toolui.inspect.title"), value: entry.title.isEmpty ? "—" : entry.title)
                LabeledContent(L10n.t("toolui.inspect.application"), value: entry.app)
                LabeledContent(L10n.t("toolui.inspect.process_id"), value: String(entry.pid))
                LabeledContent(L10n.t("toolui.inspect.window_id"), value: String(entry.id))
                LabeledContent(L10n.t("toolui.inspect.position"), value: String(format: "%.0f, %.0f",
                                                                                entry.bounds.origin.x, entry.bounds.origin.y))
                LabeledContent(L10n.t("toolui.inspect.size"), value: String(format: "%.0f × %.0f",
                                                                            entry.bounds.width, entry.bounds.height))
                LabeledContent(L10n.t("toolui.inspect.layer"), value: String(entry.layer))
                LabeledContent(L10n.t("toolui.inspect.opacity"), value: String(format: "%.0f%%", entry.alpha * 100))
                HStack {
                    Spacer()
                    Button(L10n.t("toolui.inspect.copy_info")) {
                        ToolWindows.copyToClipboard(L10n.t(
                            "toolui.inspect.copy_template",
                            entry.title, entry.app, Int(entry.pid), Int(entry.id),
                            Int(entry.bounds.origin.x), Int(entry.bounds.origin.y),
                            Int(entry.bounds.width), Int(entry.bounds.height),
                            entry.layer, Int(entry.alpha * 100)
                        ))
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
