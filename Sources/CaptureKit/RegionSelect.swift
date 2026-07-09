// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Region selection overlay: one borderless window per display with dimming,
// crosshair, selection rectangle and size label. Hovering highlights the
// window under the cursor; a plain click captures it (drag overrides).
// Esc cancels.
// ponytail: ellipse/freehand shapes and a magnifier layer on if anyone asks

import AppKit

@MainActor
public final class RegionSelectController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    public init() {}

    /// Shows the overlay on all displays; returns the selection in Cocoa global coordinates, or nil if cancelled.
    public func selectRegion() async -> CGRect? {
        // snapshot before our overlays exist; windows won't move while dimmed
        let snapCandidates = WindowLister.onScreenWindows(excludingPID: ProcessInfo.processInfo.processIdentifier)
            .map { SnapWindow(rect: ScreenCoordinates.cocoaFromCG($0.frame), name: $0.ownerName) }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            for screen in NSScreen.screens {
                let window = OverlayWindow(screen: screen, snapCandidates: snapCandidates) { [weak self] rect in
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

/// A snappable window: Cocoa global rect, front-to-back order preserved.
struct SnapWindow {
    let rect: NSRect
    let name: String
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, snapCandidates: [SnapWindow], onFinish: @escaping (CGRect?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // window rects arrive in Cocoa global coordinates; make them view-local
        let local = snapCandidates
            .filter { $0.rect.intersects(screen.frame) }
            .map { SnapWindow(rect: $0.rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), name: $0.name) }
        let view = RegionSelectView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                    snapCandidates: local, onFinish: onFinish)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

private final class RegionSelectView: NSView {
    private let onFinish: (CGRect?) -> Void
    private let snapCandidates: [SnapWindow]
    private var dragStart: NSPoint?
    private var selection: NSRect = .zero
    private var mouseLocation: NSPoint = .zero
    private var hovered: SnapWindow?

    /// Drags smaller than this act as a click (window snap), not a region.
    private static let dragThreshold: CGFloat = 5

    init(frame: NSRect, snapCandidates: [SnapWindow], onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        self.snapCandidates = snapCandidates
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
        updateHover(to: dragStart!)
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
        defer { dragStart = nil }
        guard let window else { return onFinish(nil) }
        if selection.width >= Self.dragThreshold, selection.height >= Self.dragThreshold {
            onFinish(window.convertToScreen(selection))
        } else if let hovered {
            onFinish(window.convertToScreen(hovered.rect))
        } else {
            onFinish(nil) // plain click on bare desktop cancels
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish(nil)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(to: convert(event.locationInWindow, from: nil))
    }

    private func updateHover(to point: NSPoint) {
        mouseLocation = point
        // candidates are front-to-back: first hit is the visible window
        hovered = snapCandidates.first { $0.rect.contains(point) }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        if selection.width >= 1 {
            punchHole(selection, in: context)
            drawLabel("\(Int(selection.width)) × \(Int(selection.height))", above: selection)
        } else if let hovered {
            punchHole(hovered.rect, in: context)
            drawLabel(hovered.name, above: hovered.rect.intersection(bounds))
            drawCrosshair()
        } else {
            drawCrosshair()
        }
    }

    private func punchHole(_ rect: NSRect, in context: CGContext) {
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()
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

    private func drawLabel(_ text: String, above rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let padding: CGFloat = 4
        var origin = NSPoint(x: max(rect.minX, 0), y: rect.maxY + padding)
        if origin.y + size.height > bounds.height {
            origin.y = rect.maxY - size.height - padding
        }
        let background = NSRect(x: origin.x - padding, y: origin.y - 2,
                                width: size.width + padding * 2, height: size.height + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 3, yRadius: 3).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
