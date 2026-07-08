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
    @Published var canUndo = false
    @Published var canRedo = false
    weak var canvas: EditorCanvasView?
}

public struct EditorView: View {
    let image: CGImage
    let onComplete: (CGImage?) -> Void
    @StateObject private var state = EditorState()

    public init(image: CGImage, onComplete: @escaping (CGImage?) -> Void) {
        self.image = image
        self.onComplete = onComplete
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

                Slider(value: $state.lineWidth, in: 1...10) {
                    EmptyView()
                }
                .frame(width: 100)
                .help("Line width")

                Spacer()

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
        state.canvas = canvas
        return canvas
    }

    func updateNSView(_ canvas: EditorCanvasView, context: Context) {
        canvas.currentTool = state.tool
        canvas.currentColor = NSColor(state.color)
        canvas.currentLineWidth = state.lineWidth
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
