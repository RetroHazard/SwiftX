// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// Region selection overlay: one borderless window per display with dimming,
// crosshair, selection rectangle and size label. Hovering highlights the
// window under the cursor; a plain click captures it (drag overrides).
// Tab cycles rectangle/ellipse/freehand shapes, M toggles the magnifier,
// F toggles fixed-size mode, drags auto-snap to preset sizes. Esc cancels.

import AppKit

public enum RegionShape: String, CaseIterable {
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case freehand = "Freehand"
}

/// A completed region selection. `rect` is in Cocoa global coordinates;
/// non-rectangular shapes carry the geometry needed to mask the capture.
public struct RegionSelection {
    public let rect: CGRect
    public let shape: RegionShape
    /// Cocoa-global outline points, only populated for freehand.
    public let freehandPoints: [CGPoint]

    /// Clears everything outside the shape (transparent). No-op for rectangles.
    public func applyMask(to image: CGImage) -> CGImage {
        guard shape != .rectangle, rect.width > 0, rect.height > 0 else { return image }
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        let path = CGMutablePath()
        switch shape {
        case .rectangle:
            return image
        case .ellipse:
            path.addEllipse(in: CGRect(x: 0, y: 0, width: width, height: height))
        case .freehand:
            // Cocoa global y-up matches the context's bottom-left origin
            let sx = CGFloat(width) / rect.width, sy = CGFloat(height) / rect.height
            let local = freehandPoints.map {
                CGPoint(x: ($0.x - rect.minX) * sx, y: ($0.y - rect.minY) * sy)
            }
            guard local.count >= 3 else { return image }
            path.addLines(between: local)
            path.closeSubpath()
        }
        context.addPath(path)
        context.clip()
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}

@MainActor
public final class RegionSelectController {
    private var windows: [OverlayWindow] = []
    private var continuation: CheckedContinuation<RegionSelection?, Never>?
    private let state = OverlayState()

    public init() {}

    /// Rectangle-only convenience for callers that just need a rect (recording, tools).
    public func selectRegion() async -> CGRect? {
        await selectRegionDetailed()?.rect
    }

    /// Shows the overlay on all displays; returns the selection, or nil if cancelled.
    public func selectRegionDetailed() async -> RegionSelection? {
        // snapshot before our overlays exist; windows won't move while dimmed
        let snapCandidates = WindowLister.onScreenWindows(excludingPID: ProcessInfo.processInfo.processIdentifier)
            .map { SnapWindow(rect: ScreenCoordinates.cocoaFromCG($0.frame), name: $0.ownerName) }

        // freeze each display for the magnifier before the overlays dim them
        // ponytail: magnified pixels lag live content (video etc.) - re-freeze on a timer if anyone cares
        let frozen: [CGImage?] = await withTaskGroup(of: (Int, CGImage?).self) { group in
            for (index, screen) in NSScreen.screens.enumerated() {
                group.addTask { @MainActor in
                    (index, try? await ScreenCapture.captureDisplay(screen: screen, showsCursor: false))
                }
            }
            var images = [CGImage?](repeating: nil, count: NSScreen.screens.count)
            for await (index, image) in group { images[index] = image }
            return images
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            NSApp.activate(ignoringOtherApps: true)
            for (index, screen) in NSScreen.screens.enumerated() {
                let window = OverlayWindow(screen: screen, snapCandidates: snapCandidates,
                                           state: state, frozenScreen: frozen[index]) { [weak self] selection in
                    self?.finish(selection)
                }
                window.makeKeyAndOrderFront(nil)
                windows.append(window)
            }
            state.refresh = { [weak self] in
                self?.windows.forEach { $0.contentView?.needsDisplay = true }
            }
        }
    }

    private func finish(_ selection: RegionSelection?) {
        guard let continuation else { return } // first window to finish wins
        self.continuation = nil
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let valid = selection.flatMap { $0.rect.width >= 1 && $0.rect.height >= 1 ? $0 : nil }
        continuation.resume(returning: valid)
    }
}

/// A snappable window: Cocoa global rect, front-to-back order preserved.
struct SnapWindow {
    let rect: NSRect
    let name: String
}

/// Mode state shared by every display's overlay so Tab/M/F apply everywhere.
@MainActor
private final class OverlayState {
    var shape: RegionShape = .rectangle
    var showMagnifier = true            // ShareX default ShowMagnifier
    var fixedMode = false
    let fixedSize = NSSize(width: 250, height: 250) // ShareX default FixedSize
    var refresh: () -> Void = {}
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, snapCandidates: [SnapWindow], state: OverlayState,
         frozenScreen: CGImage?, onFinish: @escaping (RegionSelection?) -> Void) {
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
                                    snapCandidates: local, state: state,
                                    frozenScreen: frozenScreen, onFinish: onFinish)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
}

private final class RegionSelectView: NSView {
    private let onFinish: (RegionSelection?) -> Void
    private let snapCandidates: [SnapWindow]
    private let state: OverlayState
    private let frozenScreen: CGImage?
    private var dragStart: NSPoint?
    private var selection: NSRect = .zero
    private var freehandPoints: [NSPoint] = []
    private var mouseLocation: NSPoint = .zero
    private var hovered: SnapWindow?

    /// Drags smaller than this act as a click (window snap), not a region.
    private static let dragThreshold: CGFloat = 5
    /// ShareX defaults: 240p/360p/480p/720p/1080p, snap within distance 30.
    private static let snapSizes: [NSSize] = [
        NSSize(width: 426, height: 240), NSSize(width: 640, height: 360),
        NSSize(width: 854, height: 480), NSSize(width: 1280, height: 720),
        NSSize(width: 1920, height: 1080)
    ]
    private static let snapDistance: CGFloat = 30
    /// ShareX defaults: 15 pixels magnified 10x.
    private static let magnifierPixelCount = 15
    private static let magnifierPixelSize: CGFloat = 10

    init(frame: NSRect, snapCandidates: [SnapWindow], state: OverlayState,
         frozenScreen: CGImage?, onFinish: @escaping (RegionSelection?) -> Void) {
        self.onFinish = onFinish
        self.snapCandidates = snapCandidates
        self.state = state
        self.frozenScreen = frozenScreen
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
        selection = state.fixedMode ? fixedRect(at: dragStart!) : .zero
        freehandPoints = state.shape == .freehand ? [dragStart!] : []
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        var current = convert(event.locationInWindow, from: nil)
        mouseLocation = current
        if state.fixedMode {
            selection = fixedRect(at: current)
        } else if state.shape == .freehand {
            freehandPoints.append(current)
            selection = boundingBox(of: freehandPoints)
        } else {
            current = snapped(current, from: dragStart)
            selection = NSRect(
                x: min(dragStart.x, current.x),
                y: min(dragStart.y, current.y),
                width: abs(current.x - dragStart.x),
                height: abs(current.y - dragStart.y)
            )
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard let window else { return onFinish(nil) }
        if state.fixedMode {
            let rect = fixedRect(at: convert(event.locationInWindow, from: nil))
            onFinish(RegionSelection(rect: window.convertToScreen(rect), shape: .rectangle, freehandPoints: []))
        } else if selection.width >= Self.dragThreshold, selection.height >= Self.dragThreshold {
            let global = freehandPoints.map { window.convertPoint(toScreen: $0) }
            onFinish(RegionSelection(rect: window.convertToScreen(selection),
                                     shape: state.shape, freehandPoints: global))
        } else if let hovered {
            onFinish(RegionSelection(rect: window.convertToScreen(hovered.rect), shape: .rectangle, freehandPoints: []))
        } else {
            onFinish(nil) // plain click on bare desktop cancels
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onFinish(nil)
            return
        case 48: // Tab: cycle shape
            let all = RegionShape.allCases
            state.shape = all[(all.firstIndex(of: state.shape)! + 1) % all.count]
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "m": state.showMagnifier.toggle()
            case "f": state.fixedMode.toggle()
            default: return
            }
        }
        state.refresh()
    }

    override func mouseMoved(with event: NSEvent) {
        // keys follow the mouse across displays
        if window?.isKeyWindow == false { window?.makeKey() }
        updateHover(to: convert(event.locationInWindow, from: nil))
    }

    private func updateHover(to point: NSPoint) {
        mouseLocation = point
        // candidates are front-to-back: first hit is the visible window
        hovered = snapCandidates.first { $0.rect.contains(point) }
        needsDisplay = true
    }

    private func fixedRect(at point: NSPoint) -> NSRect {
        NSRect(x: point.x - state.fixedSize.width / 2, y: point.y - state.fixedSize.height / 2,
               width: state.fixedSize.width, height: state.fixedSize.height)
    }

    private func boundingBox(of points: [NSPoint]) -> NSRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Snaps the drag size to the nearest preset when within snapDistance.
    private func snapped(_ current: NSPoint, from start: NSPoint) -> NSPoint {
        let width = abs(current.x - start.x), height = abs(current.y - start.y)
        let best = Self.snapSizes
            .map { (size: $0, distance: hypot($0.width - width, $0.height - height)) }
            .filter { $0.distance > 0 && $0.distance < Self.snapDistance }
            .min { $0.distance < $1.distance }
        guard let best else { return current }
        return NSPoint(x: start.x + (current.x >= start.x ? best.size.width : -best.size.width),
                       y: start.y + (current.y >= start.y ? best.size.height : -best.size.height))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        let liveFixed = state.fixedMode && dragStart == nil && bounds.contains(mouseLocation)
        let shown = liveFixed ? fixedRect(at: mouseLocation) : selection

        if shown.width >= 1 {
            punchHole(shown, in: context)
            drawLabel("\(Int(shown.width)) × \(Int(shown.height))", above: shown)
        } else if let hovered {
            punchHole(hovered.rect, in: context)
            drawLabel(hovered.name, above: hovered.rect.intersection(bounds))
            drawCrosshair()
        } else {
            drawCrosshair()
        }
        if dragStart == nil || state.shape == .freehand {
            drawMagnifier(in: context)
        }
        drawHintBar()
    }

    private func punchHole(_ rect: NSRect, in context: CGContext) {
        let path: NSBezierPath
        switch dragStart != nil || selection.width >= 1 ? state.shape : .rectangle {
        case .ellipse where !state.fixedMode:
            path = NSBezierPath(ovalIn: rect)
        case .freehand where !state.fixedMode && !freehandPoints.isEmpty:
            path = NSBezierPath()
            path.move(to: freehandPoints[0])
            freehandPoints.dropFirst().forEach(path.line)
            path.close()
        default:
            path = NSBezierPath(rect: rect)
        }

        context.saveGState()
        context.setBlendMode(.clear)
        path.fill()
        context.restoreGState()

        NSColor.white.setStroke()
        path.lineWidth = 1
        path.stroke()
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

    /// Round pixel magnifier next to the cursor, fed from the pre-overlay screen freeze.
    private func drawMagnifier(in context: CGContext) {
        guard state.showMagnifier, let image = frozenScreen, bounds.contains(mouseLocation) else { return }
        let scale = CGFloat(image.width) / bounds.width
        let side = CGFloat(Self.magnifierPixelCount) * Self.magnifierPixelSize

        // keep the loupe on screen: prefer top-right of the cursor
        let offset: CGFloat = 24
        var origin = NSPoint(x: mouseLocation.x + offset, y: mouseLocation.y + offset)
        if origin.x + side > bounds.width { origin.x = mouseLocation.x - offset - side }
        if origin.y + side > bounds.height { origin.y = mouseLocation.y - offset - side }
        let magRect = NSRect(origin: origin, size: NSSize(width: side, height: side))
        let center = NSPoint(x: magRect.midX, y: magRect.midY)

        // cursor position in image pixels (image is top-left origin, y-down)
        let cx = mouseLocation.x * scale
        let cy = (bounds.height - mouseLocation.y) * scale

        // crop a little more than the visible pixel count, clamped to the image
        let halfSource = CGFloat(Self.magnifierPixelCount) / 2 * scale + scale
        let source = CGRect(x: cx - halfSource, y: cy - halfSource,
                            width: halfSource * 2, height: halfSource * 2)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !source.isEmpty, let crop = image.cropping(to: source) else { return }

        context.saveGState()
        context.addEllipse(in: magRect)
        context.clip()
        NSColor.black.setFill()
        magRect.fill()
        context.interpolationQuality = .none
        // map image pixels -> view points: pixelSize/scale per pixel, y flipped
        let unit = Self.magnifierPixelSize / scale
        context.draw(crop, in: CGRect(x: center.x + (source.minX - cx) * unit,
                                      y: center.y + (cy - source.maxY) * unit,
                                      width: source.width * unit,
                                      height: source.height * unit))
        context.restoreGState()

        // center pixel outline + loupe border
        NSColor.systemRed.setStroke()
        let px = floor(cx / scale) * scale, py = floor(cy / scale) * scale
        let pixel = NSRect(x: center.x + (px - cx) * unit,
                           y: center.y + (cy - py) * unit - Self.magnifierPixelSize,
                           width: Self.magnifierPixelSize, height: Self.magnifierPixelSize)
        NSBezierPath(rect: pixel).stroke()
        NSColor.white.setStroke()
        let border = NSBezierPath(ovalIn: magRect)
        border.lineWidth = 2
        border.stroke()
    }

    private func drawHintBar() {
        let magnifier = frozenScreen == nil ? "" : "   M magnifier \(state.showMagnifier ? "on" : "off")"
        let fixed = state.fixedMode ? "on (\(Int(state.fixedSize.width))×\(Int(state.fixedSize.height)))" : "off"
        let text = "⇥ shape: \(state.shape.rawValue.lowercased())\(magnifier)   F fixed size \(fixed)   esc cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(x: (bounds.width - size.width) / 2, y: 14)
        let background = NSRect(x: origin.x - 10, y: origin.y - 5,
                                width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: background, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin, withAttributes: attributes)
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
