// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import SwiftUI

@MainActor
final class EditorState: ObservableObject {
    @Published var tool: AnnotationTool = .rectangle
    @Published var color: Color = Color(nsColor: .systemRed)
    @Published var lineWidth: CGFloat = 3
    @Published var fillColor: Color = .clear
    @Published var shadow = false
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoom: CGFloat = 1
    /// Updated when crop shrinks the canvas; nil until the canvas exists.
    @Published var canvasSize: NSSize?
    weak var canvas: EditorCanvasView?
}

public struct EditorView: View {
    let image: CGImage
    let onComplete: (CGImage?) -> Void
    @StateObject private var state = EditorState()
    @State private var showExpandCanvas = false

    public init(image: CGImage, onComplete: @escaping (CGImage?) -> Void) {
        self.image = image
        self.onComplete = onComplete
    }

    private var canvasPointSize: NSSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $state.tool) {
                    ForEach(AnnotationTool.allCases) { tool in
                        Image(systemName: tool.symbolName)
                            .help(tool.displayName)
                            .tag(tool)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                ColorPicker("", selection: $state.color, supportsOpacity: false)
                    .labelsHidden()
                    .help("Stroke color")

                ColorPicker("", selection: $state.fillColor, supportsOpacity: true)
                    .labelsHidden()
                    .help("Fill color for rectangle/ellipse (transparent = no fill)")

                Toggle(isOn: $state.shadow) {
                    Image(systemName: "square.fill.on.square")
                }
                .toggleStyle(.button)
                .help("Drop shadow")

                Slider(value: $state.lineWidth, in: 1...10) {
                    EmptyView()
                }
                .frame(width: 100)
                .help("Line width")

                Spacer()

                Button {
                    state.zoom = max(0.25, state.zoom / 1.25)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .keyboardShortcut("-", modifiers: .command)
                .help("Zoom out")

                Text("\(Int((state.zoom * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
                    .onTapGesture { state.zoom = 1 }

                Button {
                    state.zoom = min(4, state.zoom * 1.25)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .keyboardShortcut("+", modifiers: .command)
                .help("Zoom in")

                Button {
                    showExpandCanvas.toggle()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right.square")
                }
                .help("Expand canvas")
                .popover(isPresented: $showExpandCanvas) {
                    ExpandCanvasForm(state: state, isPresented: $showExpandCanvas)
                }

                Button {
                    state.canvas?.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!state.canUndo)
                .keyboardShortcut("z", modifiers: .command)

                Button {
                    state.canvas?.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!state.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .padding(8)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                CanvasRepresentable(image: image, state: state)
                    .frame(width: (state.canvasSize ?? canvasPointSize).width * state.zoom,
                           height: (state.canvasSize ?? canvasPointSize).height * state.zoom)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete(nil)
                }
                .keyboardShortcut(.cancelAction)
                Button("Continue") {
                    onComplete(state.canvas?.renderFinalImage())
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(8)
        }
    }
}

private struct CanvasRepresentable: NSViewRepresentable {
    let image: CGImage
    @ObservedObject var state: EditorState

    func makeNSView(context: Context) -> EditorCanvasView {
        let canvas = EditorCanvasView(image: image)
        canvas.onHistoryChanged = { [weak state, weak canvas] in
            guard let state, let canvas else { return }
            state.canUndo = canvas.canUndo
            state.canRedo = canvas.canRedo
        }
        canvas.onCanvasSizeChanged = { [weak state] size in
            state?.canvasSize = size
        }
        state.canvas = canvas
        return canvas
    }

    func updateNSView(_ canvas: EditorCanvasView, context: Context) {
        canvas.currentTool = state.tool
        // setters apply to the current selection when one exists
        canvas.setColor(NSColor(state.color))
        canvas.setFillColor(NSColor(state.fillColor))
        canvas.setShadow(state.shadow)
        canvas.setLineWidth(state.lineWidth)
        canvas.setZoom(state.zoom)
    }
}

/// Per-edge padding form for growing the canvas (C# canvas size tool).
private struct ExpandCanvasForm: View {
    @ObservedObject var state: EditorState
    @Binding var isPresented: Bool
    @State private var top = 0
    @State private var left = 0
    @State private var bottom = 0
    @State private var right = 0
    @State private var fill: Color = .white

    var body: some View {
        VStack(spacing: 10) {
            Text("Expand canvas (points)").font(.headline)
            Grid {
                GridRow {
                    Text("Top"); TextField("", value: $top, format: .number).frame(width: 60)
                    Text("Bottom"); TextField("", value: $bottom, format: .number).frame(width: 60)
                }
                GridRow {
                    Text("Left"); TextField("", value: $left, format: .number).frame(width: 60)
                    Text("Right"); TextField("", value: $right, format: .number).frame(width: 60)
                }
            }
            ColorPicker("Fill color", selection: $fill, supportsOpacity: true)
            Button("Expand") {
                state.canvas?.expandCanvas(
                    top: CGFloat(top), left: CGFloat(left),
                    bottom: CGFloat(bottom), right: CGFloat(right),
                    color: NSColor(fill)
                )
                isPresented = false
            }
            .keyboardShortcut(.defaultAction)
            .disabled(top <= 0 && left <= 0 && bottom <= 0 && right <= 0)
        }
        .padding(12)
    }
}

/// Presents the editor in its own window; resolves when the user chooses
/// Continue (edited image), Cancel (nil), or closes the window (nil).
@MainActor
public enum ImageEditorPresenter {
    private final class WindowDelegate: NSObject, NSWindowDelegate {
        var onClose: (() -> Void)?
        func windowWillClose(_ notification: Notification) {
            onClose?()
        }
    }

    private static var activeDelegates: [WindowDelegate] = []

    public static func present(image: CGImage) async -> CGImage? {
        await withCheckedContinuation { continuation in
          // continuation body runs synchronously on the caller's (main) thread
          MainActor.assumeIsolated {
            var finished = false
            let delegate = WindowDelegate()
            activeDelegates.append(delegate)

            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ShareX Image Editor"
            window.isReleasedWhenClosed = false
            window.delegate = delegate

            // nested funcs don't inherit the enclosing closure's isolation;
            // every caller (buttons, windowWillClose) is on the main thread
            func finish(_ result: CGImage?) {
                MainActor.assumeIsolated {
                    guard !finished else { return }
                    finished = true
                    activeDelegates.removeAll { $0 === delegate }
                    if window.isVisible {
                        window.delegate = nil
                        window.close()
                    }
                    continuation.resume(returning: result)
                }
            }

            delegate.onClose = { finish(nil) }
            window.contentView = NSHostingView(rootView: EditorView(image: image) { finish($0) })

            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let imageSize = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            let chrome = NSSize(width: 24, height: 110)
            var contentSize = NSSize(width: imageSize.width + chrome.width, height: imageSize.height + chrome.height)
            if let visible = NSScreen.main?.visibleFrame {
                contentSize.width = min(contentSize.width, visible.width * 0.9)
                contentSize.height = min(contentSize.height, visible.height * 0.9)
            }
            window.setContentSize(contentSize)
            window.center()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
          }
        }
    }
}
