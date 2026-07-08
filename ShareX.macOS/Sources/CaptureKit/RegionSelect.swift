// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Region selection overlay: one borderless window per display with dimming,
// crosshair, selection rectangle and size label. Esc or a zero-size click cancels.
// ponytail: rectangle selection only; ellipse/freehand/window-snap/magnifier layer on in later Phase 1 iterations

import AppKit

@MainActor
public final class RegionSelectController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    public init() {}

    /// Shows the overlay on all displays; returns the selection in Cocoa global coordinates, or nil if cancelled.
    public func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            for screen in NSScreen.screens {
                let window = OverlayWindow(screen: screen) { [weak self] rect in
                    self?.finish(rect)
                }
                window.makeKeyAndOrderFront(nil)
                windows.append(window)
            }
        }
    }

    private func finish(_ rect: CGRect?) {
        guard let continuation else { return } // first window to finish wins
        self.continuation = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let valid = rect.flatMap { $0.width >= 1 && $0.height >= 1 ? $0 : nil }
        continuation.resume(returning: valid)
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RegionSelectView(frame: NSRect(origin: .zero, size: screen.frame.size), onFinish: onFinish)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

private final class RegionSelectView: NSView {
    private let onFinish: (CGRect?) -> Void
    private var dragStart: NSPoint?
    private var selection: NSRect = .zero
    private var mouseLocation: NSPoint = .zero

    init(frame: NSRect, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        selection = .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selection = NSRect(
            x: min(dragStart.x, current.x),
            y: min(dragStart.y, current.y),
            width: abs(current.x - dragStart.x),
            height: abs(current.y - dragStart.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil, selection.width >= 1, selection.height >= 1, let window else {
            onFinish(nil) // plain click cancels; window-under-cursor selection comes with window snapping
            return
        }
        onFinish(window.convertToScreen(selection))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish(nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        if selection.width >= 1 {
            // punch a clear hole where the selection is
            context.setBlendMode(.clear)
            context.fill(selection)
            context.setBlendMode(.normal)

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()

            drawSizeLabel()
        } else {
            drawCrosshair()
        }
    }

    private func drawCrosshair() {
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: mouseLocation.x, y: 0))
        path.line(to: NSPoint(x: mouseLocation.x, y: bounds.height))
        path.move(to: NSPoint(x: 0, y: mouseLocation.y))
        path.line(to: NSPoint(x: bounds.width, y: mouseLocation.y))
        path.stroke()
    }

    private func drawSizeLabel() {
        let text = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 4
        var origin = NSPoint(x: selection.minX, y: selection.maxY + padding)
        if origin.y + size.height > bounds.height {
            origin.y = selection.maxY - size.height - padding
        }
        let background = NSRect(x: origin.x - padding, y: origin.y - 2,
                                width: size.width + padding * 2, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
