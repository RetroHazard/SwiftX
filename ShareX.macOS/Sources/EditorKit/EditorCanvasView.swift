// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Annotation canvas: displays the image at screen scale, handles tool input,
// selection/move/resize (Screenshot.app-style), snapshot-based undo/redo, and
// renders the final image at full pixel size. The same drawShape routine draws
// both the live view and the export, so preview and output cannot drift apart.

import AppKit
import CoreImage

@MainActor
public final class EditorCanvasView: NSView {
    public private(set) var baseImage: CGImage
    public var currentTool: AnnotationTool = .rectangle
    public private(set) var currentColor: NSColor = .systemRed
    public private(set) var currentLineWidth: CGFloat = 3
    public var onHistoryChanged: (() -> Void)?
    /// Fired when crop changes the canvas dimensions (SwiftUI must re-frame).
    public var onCanvasSizeChanged: ((NSSize) -> Void)?

    /// Crop mutates the base image, so history snapshots carry both.
    /// CGImages are immutable - snapshots hold references, not copies.
    struct Snapshot {
        let image: CGImage
        let shapes: [AnnotationShape]
    }

    private(set) var shapes: [AnnotationShape] = []
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    public private(set) var selectedShapeID: UUID?

    private enum DragMode {
        case none
        case draw
        case move
        case resize(handle: Int)
    }

    private var dragMode: DragMode = .none
    private var dragStart: CGPoint = .zero
    private var dragOriginalShape: AnnotationShape?
    private var dragSnapshot: [AnnotationShape]?
    private var draft: AnnotationShape?
    private var activeTextField: NSTextField?

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Logical (point) size of the canvas; SwiftUI layout must honor this.
    public private(set) var canvasSize: NSSize
    private let displayScale: CGFloat

    /// View magnification. Shapes stay in canvas points; input divides by
    /// zoom, drawing multiplies. Pan comes free from the enclosing ScrollView.
    public private(set) var zoom: CGFloat = 1

    /// What the view actually occupies on screen (canvas points x zoom).
    public var displaySize: NSSize {
        NSSize(width: canvasSize.width * zoom, height: canvasSize.height * zoom)
    }

    /// SwiftUI owns the zoom value and also scales the layout frame itself,
    /// so this only refreshes the view - no state published back mid-update.
    public func setZoom(_ value: CGFloat) {
        let clamped = min(4, max(0.25, value))
        guard abs(clamped - zoom) > 0.001 else { return }
        commitTextEntry() // the field's frame is in view coords of the old zoom
        zoom = clamped
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    public init(image: CGImage) {
        self.baseImage = image
        self.displayScale = NSScreen.main?.backingScaleFactor ?? 2
        self.canvasSize = NSSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
        super.init(frame: NSRect(origin: .zero, size: canvasSize))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    // without this, the representable collapses to zero inside a SwiftUI ScrollView
    public override var intrinsicContentSize: NSSize { displaySize }

    /// Event location in canvas points (undoes the zoom).
    private func canvasPoint(for event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / zoom, y: p.y / zoom)
    }

    // MARK: - Effect variants (blur/pixelate draw regions from these; reset on crop/undo)

    private var cachedBlurredBase: CGImage??
    private var cachedPixelatedBase: CGImage??

    private var blurredBase: CGImage? {
        if let cached = cachedBlurredBase { return cached }
        let input = CIImage(cgImage: baseImage)
        var result: CGImage?
        if let filter = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputRadiusKey: 12.0
        ]), let output = filter.outputImage?.cropped(to: input.extent) {
            result = CIContext().createCGImage(output, from: output.extent)
        }
        cachedBlurredBase = .some(result)
        return result
    }

    private var pixelatedBase: CGImage? {
        if let cached = cachedPixelatedBase { return cached }
        let input = CIImage(cgImage: baseImage)
        var result: CGImage?
        if let filter = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputScaleKey: max(8.0, Double(baseImage.width) / 80.0),
            kCIInputCenterKey: CIVector(x: 0, y: 0)
        ]), let output = filter.outputImage?.cropped(to: input.extent) {
            result = CIContext().createCGImage(output, from: output.extent)
        }
        cachedPixelatedBase = .some(result)
        return result
    }

    private func setBaseImage(_ image: CGImage) {
        baseImage = image
        cachedBlurredBase = nil
        cachedPixelatedBase = nil
        canvasSize = NSSize(width: CGFloat(image.width) / displayScale, height: CGFloat(image.height) / displayScale)
        invalidateIntrinsicContentSize()
        onCanvasSizeChanged?(canvasSize)
    }

    // MARK: - History (whole-array snapshots: moves/resizes mutate, not append)

    private func pushHistory() {
        undoStack.append(Snapshot(image: baseImage, shapes: shapes))
        redoStack.removeAll()
        onHistoryChanged?()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: baseImage, shapes: shapes))
        restore(previous)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: baseImage, shapes: shapes))
        restore(next)
    }

    private func restore(_ snapshot: Snapshot) {
        if snapshot.image !== baseImage {
            setBaseImage(snapshot.image)
        }
        shapes = snapshot.shapes
        clampSelection()
        needsDisplay = true
        onHistoryChanged?()
    }

    private func clampSelection() {
        if let selectedShapeID, !shapes.contains(where: { $0.id == selectedShapeID }) {
            self.selectedShapeID = nil
        }
    }

    // MARK: - Mutations

    public func addShape(_ shape: AnnotationShape) {
        assert(shape.tool != .select, "select is a mode, not a shape")
        pushHistory()
        shapes.append(shape)
        selectedShapeID = shape.id // Screenshot.app-style: new shape is immediately manipulable
        needsDisplay = true
    }

    public func selectShape(id: UUID?) {
        selectedShapeID = id
        needsDisplay = true
    }

    public func deleteSelectedShape() {
        guard let index = selectedIndex else { return }
        pushHistory()
        shapes.remove(at: index)
        selectedShapeID = nil
        needsDisplay = true
    }

    /// Applies to the selection when one exists; always becomes the tool default.
    public func setColor(_ color: NSColor) {
        guard !isEqualColor(color, currentColor) else { return }
        currentColor = color
        if let index = selectedIndex {
            pushHistory()
            shapes[index].color = color
            needsDisplay = true
        }
    }

    public func setLineWidth(_ width: CGFloat) {
        guard abs(width - currentLineWidth) > 0.01 else { return }
        currentLineWidth = width
        if let index = selectedIndex {
            pushHistory()
            shapes[index].lineWidth = width
            needsDisplay = true
        }
    }

    private var selectedIndex: Int? {
        shapes.firstIndex { $0.id == selectedShapeID }
    }

    private func isEqualColor(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return a == b }
        return abs(x.redComponent - y.redComponent) < 0.001
            && abs(x.greenComponent - y.greenComponent) < 0.001
            && abs(x.blueComponent - y.blueComponent) < 0.001
            && abs(x.alphaComponent - y.alphaComponent) < 0.001
    }

    // MARK: - Hit testing

    func shapeIndex(at point: CGPoint) -> Int? {
        // topmost first (last drawn wins)
        for index in shapes.indices.reversed() where hits(shapes[index], at: point) {
            return index
        }
        return nil
    }

    private func hits(_ shape: AnnotationShape, at point: CGPoint) -> Bool {
        let slop: CGFloat = 6
        switch shape.tool {
        case .line, .arrow:
            guard shape.points.count >= 2 else { return false }
            return distance(from: point, toSegment: shape.points[0], shape.points[1]) <= max(8, shape.lineWidth)
        case .freehand:
            guard shape.points.count > 1 else { return false }
            for i in 0..<(shape.points.count - 1) where distance(from: point, toSegment: shape.points[i], shape.points[i + 1]) <= 8 {
                return true
            }
            return false
        case .text:
            return textBounds(shape).insetBy(dx: -slop, dy: -slop).contains(point)
        default:
            return shape.rect.insetBy(dx: -slop, dy: -slop).contains(point)
        }
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func textBounds(_ shape: AnnotationShape) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: shape.fontSize, weight: .semibold)
        ]
        let size = NSString(string: shape.text).size(withAttributes: attributes)
        return CGRect(origin: shape.rect.origin, size: size)
    }

    /// Handle positions: corners for rect-based shapes, endpoints for line/arrow,
    /// corners + tail tip (index 4) for speech balloons.
    private func handlePoints(for shape: AnnotationShape) -> [CGPoint] {
        switch shape.tool {
        case .line, .arrow:
            return shape.points.count >= 2 ? [shape.points[0], shape.points[1]] : []
        case .freehand, .text:
            return [] // move-only
        case .speechBalloon:
            let r = shape.rect
            var handles = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                           CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
            if let tail = shape.points.first {
                handles.append(tail)
            }
            return handles
        default:
            let r = shape.rect
            return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                    CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        }
    }

    private func handleIndex(at point: CGPoint, for shape: AnnotationShape) -> Int? {
        handlePoints(for: shape).firstIndex { hypot($0.x - point.x, $0.y - point.y) <= 7 }
    }

    // MARK: - Input

    public override func mouseDown(with event: NSEvent) {
        commitTextEntry()
        window?.makeFirstResponder(self)
        let point = canvasPoint(for: event)

        // double-click a text shape or balloon re-opens it for editing, regardless of tool
        if event.clickCount == 2, let index = shapeIndex(at: point) {
            let shape = shapes[index]
            if shape.tool == .text {
                pushHistory()
                shapes.remove(at: index)
                selectedShapeID = nil
                needsDisplay = true
                beginTextEntry(at: shape.rect.origin, prefilled: shape.text, color: shape.color)
                return
            }
            if shape.tool == .speechBalloon {
                beginTextEntry(at: CGPoint(x: shape.rect.minX + 8, y: shape.rect.minY + 8),
                               prefilled: shape.text, color: shape.color, target: shape.id)
                return
            }
        }

        // grabbing a handle of the selected shape resizes it, regardless of tool
        if let index = selectedIndex, let handle = handleIndex(at: point, for: shapes[index]) {
            dragMode = .resize(handle: handle)
            dragOriginalShape = shapes[index]
            dragSnapshot = shapes
            dragStart = point
            return
        }

        if currentTool == .select {
            if let index = shapeIndex(at: point) {
                selectedShapeID = shapes[index].id
                dragMode = .move
                dragOriginalShape = shapes[index]
                dragSnapshot = shapes
                dragStart = point
            } else {
                selectedShapeID = nil
                dragMode = .none
            }
            needsDisplay = true
            return
        }

        if currentTool == .text {
            beginTextEntry(at: point)
            return
        }
        if currentTool == .image {
            placeImageStamp(at: point)
            return
        }
        if currentTool == .step {
            var shape = AnnotationShape(tool: .step)
            shape.number = (shapes.filter { $0.tool == .step }.map(\.number).max() ?? 0) + 1
            shape.rect = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
            shape.color = currentColor
            addShape(shape)
            return
        }

        dragStart = point
        dragMode = .draw
        var shape = AnnotationShape(tool: currentTool)
        // C# SmartEraserDrawingShape samples the canvas color where the drag starts
        shape.color = currentTool == .smartEraser ? baseColor(at: point) : currentColor
        shape.lineWidth = currentLineWidth
        shape.points = [point, point]
        draft = shape
    }

    public override func mouseDragged(with event: NSEvent) {
        let point = canvasPoint(for: event)

        switch dragMode {
        case .draw:
            guard var shape = draft else { return }
            switch shape.tool {
            case .freehand:
                shape.points.append(point)
            case .line, .arrow:
                shape.points = [dragStart, point]
            default:
                shape.rect = normalizedRect(from: dragStart, to: point)
            }
            draft = shape
        case .move:
            pushDragHistoryOnce()
            guard let original = dragOriginalShape, let index = selectedIndex else { return }
            let delta = CGPoint(x: point.x - dragStart.x, y: point.y - dragStart.y)
            shapes[index] = translated(original, by: delta)
        case .resize(let handle):
            pushDragHistoryOnce()
            guard let original = dragOriginalShape, let index = selectedIndex else { return }
            shapes[index] = resized(original, handle: handle, to: point)
        case .none:
            return
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        defer {
            dragMode = .none
            dragOriginalShape = nil
            dragSnapshot = nil
        }
        guard case .draw = dragMode, var shape = draft else { return }
        draft = nil
        let point = canvasPoint(for: event)
        let dragDistance = hypot(point.x - dragStart.x, point.y - dragStart.y)
        guard dragDistance >= 3 || shape.tool == .freehand else {
            needsDisplay = true
            return
        }

        if shape.tool == .crop {
            applyCrop(shape.rect)
            return
        }
        if shape.tool == .cutOut {
            applyCutOut(shape.rect)
            return
        }
        if shape.tool == .speechBalloon {
            // default tail: below-left of the balloon, pointing away
            shape.points = [CGPoint(x: shape.rect.minX + shape.rect.width * 0.25,
                                    y: shape.rect.maxY + 30)]
            addShape(shape)
            beginTextEntry(at: CGPoint(x: shape.rect.minX + 8, y: shape.rect.minY + 8), target: shape.id)
            return
        }
        addShape(shape)
    }

    /// Crops the base image to the given canvas-point rect; shapes translate
    /// with the image. Undoable - snapshots carry the image.
    func applyCrop(_ rectInPoints: CGRect) {
        let rect = rectInPoints.intersection(CGRect(origin: .zero, size: canvasSize))
        guard rect.width >= 4, rect.height >= 4 else { return }
        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let pixelRect = CGRect(
            x: rect.minX * pixelsPerPoint,
            y: rect.minY * pixelsPerPoint,
            width: rect.width * pixelsPerPoint,
            height: rect.height * pixelsPerPoint
        ).integral
        guard let cropped = baseImage.cropping(to: pixelRect) else { return }

        pushHistory()
        setBaseImage(cropped)
        let delta = CGPoint(x: -rect.minX, y: -rect.minY)
        shapes = shapes.map { translated($0, by: delta) }
        selectedShapeID = nil
        needsDisplay = true
    }

    /// Grows the canvas by per-edge padding (canvas points) filled with a
    /// color; shapes keep their position relative to the original image.
    /// Undoable like crop - the snapshot carries the image.
    public func expandCanvas(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat, color: NSColor) {
        let top = max(0, top), left = max(0, left), bottom = max(0, bottom), right = max(0, right)
        guard top + left + bottom + right > 0 else { return }

        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let newWidth = baseImage.width + Int((left + right) * pixelsPerPoint)
        let newHeight = baseImage.height + Int((top + bottom) * pixelsPerPoint)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        if let fill = color.usingColorSpace(.sRGB), fill.alphaComponent > 0 {
            context.setFillColor(fill.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        }
        // CG origin is bottom-left: the bottom padding sits under the image
        context.draw(baseImage, in: CGRect(
            x: left * pixelsPerPoint, y: bottom * pixelsPerPoint,
            width: CGFloat(baseImage.width), height: CGFloat(baseImage.height)
        ))
        guard let expanded = context.makeImage() else { return }

        pushHistory()
        setBaseImage(expanded)
        let delta = CGPoint(x: left, y: top)
        shapes = shapes.map { translated($0, by: delta) }
        needsDisplay = true
    }

    /// The band that a cut-out drag removes: wider than tall removes columns
    /// (full canvas height), otherwise rows (full width) - C# CutOutTool rules.
    func cutOutBand(for rect: CGRect) -> CGRect {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        let band = rect.width > rect.height
            ? CGRect(x: rect.minX, y: 0, width: rect.width, height: canvasSize.height)
            : CGRect(x: 0, y: rect.minY, width: canvasSize.width, height: rect.height)
        return band.intersection(canvasRect)
    }

    /// Removes the band and joins the halves. C# offers torn/wave edge effects;
    /// ponytail: straight cut only, add edge effects if anyone misses them.
    func applyCutOut(_ rectInPoints: CGRect) {
        let band = cutOutBand(for: rectInPoints)
        let horizontal = rectInPoints.width > rectInPoints.height // removes columns
        guard band.width >= 4, band.height >= 4 else { return }
        // cutting away the whole canvas is a no-op (C# IsValidShape rejects it)
        if horizontal, band.width >= canvasSize.width - 1 { return }
        if !horizontal, band.height >= canvasSize.height - 1 { return }

        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let width = baseImage.width, height = baseImage.height
        // cropping(to:) uses top-left pixel coordinates, same as the view
        let firstRect: CGRect, secondRect: CGRect
        if horizontal {
            let cutMin = (band.minX * pixelsPerPoint).rounded()
            let cutMax = (band.maxX * pixelsPerPoint).rounded()
            firstRect = CGRect(x: 0, y: 0, width: cutMin, height: CGFloat(height))
            secondRect = CGRect(x: cutMax, y: 0, width: CGFloat(width) - cutMax, height: CGFloat(height))
        } else {
            let cutMin = (band.minY * pixelsPerPoint).rounded()
            let cutMax = (band.maxY * pixelsPerPoint).rounded()
            firstRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: cutMin)
            secondRect = CGRect(x: 0, y: cutMax, width: CGFloat(width), height: CGFloat(height) - cutMax)
        }

        let newWidth = Int(firstRect.width + (horizontal ? secondRect.width : 0))
        let newHeight = Int(firstRect.height + (horizontal ? 0 : secondRect.height))
        guard let context = CGContext(
            data: nil, width: horizontal ? newWidth : width, height: horizontal ? height : newHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        // context origin is bottom-left; place the pieces accordingly
        if horizontal {
            if let first = baseImage.cropping(to: firstRect) {
                context.draw(first, in: CGRect(x: 0, y: 0, width: firstRect.width, height: CGFloat(height)))
            }
            if let second = baseImage.cropping(to: secondRect) {
                context.draw(second, in: CGRect(x: firstRect.width, y: 0, width: secondRect.width, height: CGFloat(height)))
            }
        } else {
            if let first = baseImage.cropping(to: firstRect) { // top piece stays on top
                context.draw(first, in: CGRect(x: 0, y: CGFloat(newHeight) - firstRect.height,
                                               width: CGFloat(width), height: firstRect.height))
            }
            if let second = baseImage.cropping(to: secondRect) {
                context.draw(second, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: secondRect.height))
            }
        }
        guard let joined = context.makeImage() else { return }

        pushHistory()
        setBaseImage(joined)
        // ponytail: shapes fully past the band collapse toward it; straddlers stay put
        let delta = horizontal ? CGPoint(x: -band.width, y: 0) : CGPoint(x: 0, y: -band.height)
        shapes = shapes.map { shape in
            let bounds = selectionBounds(shape)
            let isPast = horizontal ? bounds.minX >= band.maxX : bounds.minY >= band.maxY
            return isPast ? translated(shape, by: delta) : shape
        }
        selectedShapeID = nil
        needsDisplay = true
    }

    /// Color of the base image under a canvas point (smart eraser source).
    /// Redraws into a 1x1 context, so any pixel format/byte order works.
    func baseColor(at point: CGPoint) -> NSColor {
        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let px = min(max(Int(point.x * pixelsPerPoint), 0), baseImage.width - 1)
        let py = min(max(Int(point.y * pixelsPerPoint), 0), baseImage.height - 1)
        var rgba = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .white }
        // slide the image so pixel (px, py from top) lands on the 1x1 context
        context.draw(baseImage, in: CGRect(
            x: -CGFloat(px), y: -CGFloat(baseImage.height - 1 - py),
            width: CGFloat(baseImage.width), height: CGFloat(baseImage.height)
        ))
        return NSColor(red: CGFloat(rgba[0]) / 255, green: CGFloat(rgba[1]) / 255,
                       blue: CGFloat(rgba[2]) / 255, alpha: 1)
    }

    /// Image stamp: pick a file, place it centered on the click at natural
    /// size (fit to 80% of the canvas), then move/resize like any shape.
    private func placeImageStamp(at point: CGPoint) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url),
              let stamp = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }
        var size = NSSize(width: CGFloat(stamp.width) / displayScale,
                          height: CGFloat(stamp.height) / displayScale)
        let fit = min(1, canvasSize.width * 0.8 / size.width, canvasSize.height * 0.8 / size.height)
        size = NSSize(width: size.width * fit, height: size.height * fit)
        var shape = AnnotationShape(tool: .image)
        shape.stampImage = stamp
        shape.rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                            width: size.width, height: size.height)
        addShape(shape)
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            deleteSelectedShape()
        default:
            super.keyDown(with: event)
        }
    }

    /// Click-without-drag must not create an undo step; push the snapshot on first movement.
    private func pushDragHistoryOnce() {
        guard let snapshotShapes = dragSnapshot else { return }
        dragSnapshot = nil
        undoStack.append(Snapshot(image: baseImage, shapes: snapshotShapes))
        redoStack.removeAll()
        onHistoryChanged?()
    }

    private func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func translated(_ shape: AnnotationShape, by delta: CGPoint) -> AnnotationShape {
        var moved = shape
        moved.rect.origin.x += delta.x
        moved.rect.origin.y += delta.y
        moved.points = shape.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        return moved
    }

    func resized(_ shape: AnnotationShape, handle: Int, to point: CGPoint) -> AnnotationShape {
        var result = shape
        switch shape.tool {
        case .line, .arrow:
            guard result.points.count >= 2, handle < 2 else { return result }
            result.points[handle] = point
        case .speechBalloon where handle == 4:
            result.points = [point] // tail tip
        default:
            let r = shape.rect
            let anchors = [CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY),
                           CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.minY)]
            guard handle < anchors.count else { return result }
            let anchor = anchors[handle]
            var rect = normalizedRect(from: anchor, to: point)
            if shape.tool == .step { // steps stay circular
                let side = max(rect.width, rect.height)
                rect = CGRect(
                    x: point.x < anchor.x ? anchor.x - side : anchor.x,
                    y: point.y < anchor.y ? anchor.y - side : anchor.y,
                    width: side, height: side
                )
            }
            result.rect = rect
        }
        return result
    }

    // MARK: - Text entry

    /// When target is set, the committed text updates that balloon instead of
    /// creating a standalone text shape.
    private var textEntryTarget: UUID?

    private func beginTextEntry(at point: CGPoint, prefilled: String = "", color: NSColor? = nil, target: UUID? = nil) {
        textEntryTarget = target
        // the field is a subview, so its frame lives in zoomed view coordinates
        let field = NSTextField(frame: NSRect(x: point.x * zoom, y: point.y * zoom, width: 240, height: 26))
        field.font = .systemFont(ofSize: 18)
        field.textColor = color ?? currentColor
        field.stringValue = prefilled
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.isBordered = true
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    func commitTextEntry() {
        guard let field = activeTextField else { return }
        activeTextField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        let origin = CGPoint(x: field.frame.origin.x / zoom, y: field.frame.origin.y / zoom)
        let color = field.textColor ?? currentColor
        let target = textEntryTarget
        textEntryTarget = nil
        field.removeFromSuperview()

        if let target, let index = shapes.firstIndex(where: { $0.id == target }) {
            guard shapes[index].text != text else { return }
            pushHistory()
            shapes[index].text = text
            needsDisplay = true
            return
        }

        guard !text.isEmpty else { return }
        var shape = AnnotationShape(tool: .text)
        shape.text = text
        shape.rect = CGRect(origin: origin, size: .zero)
        shape.color = color
        addShape(shape)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        // everything below works in canvas points; the transform applies the zoom
        NSGraphicsContext.current?.cgContext.scaleBy(x: zoom, y: zoom)
        // use canvasSize, not bounds: after a crop, SwiftUI relayout lags a frame
        NSImage(cgImage: baseImage, size: canvasSize).draw(in: NSRect(origin: .zero, size: canvasSize))
        for shape in shapes {
            drawShape(shape)
        }
        if let draft {
            drawShape(draft)
        }
        if let index = selectedIndex {
            drawSelectionChrome(shapes[index])
        }
    }

    private func drawShape(_ shape: AnnotationShape) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        shape.color.setStroke()
        shape.color.setFill()

        switch shape.tool {
        case .select:
            break // never stored; satisfies exhaustiveness
        case .crop:
            drawMarchingRect(shape.rect)
        case .cutOut:
            // draft-only visualization: the full band that will be removed
            let band = cutOutBand(for: shape.rect)
            NSColor.systemRed.withAlphaComponent(0.25).setFill()
            band.fill(using: .sourceOver)
            drawMarchingRect(band)
        case .smartEraser:
            // color was sampled from the canvas at drag start
            shape.rect.fill()
        case .spotlight:
            // C# dims the canvas destructively; here it's a shape - movable,
            // resizable and undoable like everything else. Same visual result.
            let dimmed = NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize))
            dimmed.append(NSBezierPath(rect: shape.rect))
            dimmed.windingRule = .evenOdd
            NSColor.black.withAlphaComponent(0.7).setFill()
            dimmed.fill()
        case .magnify:
            guard shape.rect.width > 2, shape.rect.height > 2 else { break }
            context.saveGState()
            NSBezierPath(ovalIn: shape.rect).addClip()
            // 2x zoom about the shape center (C# MagnifyStrength default 200)
            let magnification: CGFloat = 2
            let center = CGPoint(x: shape.rect.midX, y: shape.rect.midY)
            let dest = CGRect(x: center.x * (1 - magnification), y: center.y * (1 - magnification),
                              width: canvasSize.width * magnification,
                              height: canvasSize.height * magnification)
            NSImage(cgImage: baseImage, size: canvasSize).draw(in: dest)
            context.restoreGState()
            let border = NSBezierPath(ovalIn: shape.rect)
            border.lineWidth = shape.lineWidth
            border.stroke()
        case .image:
            if let stamp = shape.stampImage {
                NSImage(cgImage: stamp, size: shape.rect.size).draw(in: shape.rect)
            }
        case .speechBalloon:
            drawSpeechBalloon(shape)
        case .rectangle:
            let path = NSBezierPath(rect: shape.rect)
            path.lineWidth = shape.lineWidth
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: shape.rect)
            path.lineWidth = shape.lineWidth
            path.stroke()
        case .line:
            strokeLine(shape)
        case .arrow:
            strokeLine(shape)
            drawArrowHead(shape)
        case .freehand:
            guard shape.points.count > 1 else { break }
            let path = NSBezierPath()
            path.lineWidth = shape.lineWidth
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.move(to: shape.points[0])
            shape.points.dropFirst().forEach { path.line(to: $0) }
            path.stroke()
        case .highlight:
            context.setBlendMode(.multiply)
            NSColor.yellow.setFill()
            shape.rect.fill()
        case .blur:
            drawEffectRegion(shape.rect, from: blurredBase)
        case .pixelate:
            drawEffectRegion(shape.rect, from: pixelatedBase)
        case .text:
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: shape.fontSize, weight: .semibold),
                .foregroundColor: shape.color
            ]
            NSString(string: shape.text).draw(at: shape.rect.origin, withAttributes: attributes)
        case .step:
            let circle = NSBezierPath(ovalIn: shape.rect)
            circle.fill()
            let text = NSString(string: "\(shape.number)")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: shape.rect.height * 0.55),
                .foregroundColor: NSColor.white
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: shape.rect.midX - size.width / 2, y: shape.rect.midY - size.height / 2),
                      withAttributes: attributes)
        }
    }

    private func drawMarchingRect(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.setLineDash([5, 5], count: 2, phase: 0)
        NSColor.white.setStroke()
        path.stroke()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        path.setLineDash([5, 5], count: 2, phase: 5)
        path.stroke()
    }

    private func drawSpeechBalloon(_ shape: AnnotationShape) {
        guard shape.rect.width > 2, shape.rect.height > 2 else { return }
        let radius = min(8, shape.rect.height / 4)

        // tail first; the balloon body covers its base seam
        if let tail = shape.points.first, !shape.rect.insetBy(dx: -2, dy: -2).contains(tail) {
            let center = CGPoint(x: shape.rect.midX, y: shape.rect.midY)
            let angle = atan2(tail.y - center.y, tail.x - center.x)
            let halfWidth = min(shape.rect.width, shape.rect.height) * 0.18
            let base1 = CGPoint(x: center.x + halfWidth * cos(angle + .pi / 2),
                                y: center.y + halfWidth * sin(angle + .pi / 2))
            let base2 = CGPoint(x: center.x + halfWidth * cos(angle - .pi / 2),
                                y: center.y + halfWidth * sin(angle - .pi / 2))
            let tailPath = NSBezierPath()
            tailPath.move(to: base1)
            tailPath.line(to: tail)
            tailPath.line(to: base2)
            tailPath.close()
            NSColor.white.setFill()
            tailPath.fill()
            tailPath.lineWidth = shape.lineWidth
            shape.color.setStroke()
            tailPath.stroke()
        }

        let body = NSBezierPath(roundedRect: shape.rect, xRadius: radius, yRadius: radius)
        NSColor.white.setFill()
        body.fill()
        body.lineWidth = shape.lineWidth
        shape.color.setStroke()
        body.stroke()

        if !shape.text.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: shape.fontSize, weight: .medium),
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            let inset = shape.rect.insetBy(dx: 8, dy: 6)
            let textHeight = NSString(string: shape.text).boundingRect(
                with: NSSize(width: inset.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attributes
            ).height
            let centered = NSRect(
                x: inset.minX,
                y: max(inset.minY, inset.midY - textHeight / 2),
                width: inset.width,
                height: min(inset.height, textHeight)
            )
            NSString(string: shape.text).draw(in: centered, withAttributes: attributes)
        }
    }

    private func drawSelectionChrome(_ shape: AnnotationShape) {
        let bounds = selectionBounds(shape)
        let outline = NSBezierPath(rect: bounds.insetBy(dx: -3, dy: -3))
        outline.lineWidth = 1
        NSColor.white.setStroke()
        outline.stroke()
        outline.setLineDash([4, 4], count: 2, phase: 0)
        NSColor.black.setStroke()
        outline.stroke()

        for handle in handlePoints(for: shape) {
            let rect = CGRect(x: handle.x - 4, y: handle.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor.black.setStroke()
            NSBezierPath(ovalIn: rect).stroke()
        }
    }

    private func selectionBounds(_ shape: AnnotationShape) -> CGRect {
        switch shape.tool {
        case .speechBalloon:
            guard let tail = shape.points.first else { return shape.rect }
            return shape.rect.union(CGRect(origin: tail, size: .zero))
        case .line, .arrow, .freehand:
            guard let first = shape.points.first else { return shape.rect }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in shape.points {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .text:
            return textBounds(shape)
        default:
            return shape.rect
        }
    }

    private func strokeLine(_ shape: AnnotationShape) {
        guard shape.points.count >= 2 else { return }
        let path = NSBezierPath()
        path.lineWidth = shape.lineWidth
        path.lineCapStyle = .round
        path.move(to: shape.points[0])
        path.line(to: shape.points[1])
        path.stroke()
    }

    private func drawArrowHead(_ shape: AnnotationShape) {
        guard shape.points.count >= 2 else { return }
        let start = shape.points[0], end = shape.points[1]
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = max(12, shape.lineWidth * 4)
        let spread: CGFloat = .pi / 7

        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - length * cos(angle - spread), y: end.y - length * sin(angle - spread)))
        head.line(to: CGPoint(x: end.x - length * cos(angle + spread), y: end.y - length * sin(angle + spread)))
        head.close()
        head.fill()
    }

    private func drawEffectRegion(_ rect: CGRect, from variant: CGImage?) {
        guard let variant, rect.width > 1, rect.height > 1 else { return }
        let pixelsPerPoint = CGFloat(baseImage.width) / canvasSize.width
        let pixelRect = CGRect(
            x: rect.minX * pixelsPerPoint,
            y: rect.minY * pixelsPerPoint,
            width: rect.width * pixelsPerPoint,
            height: rect.height * pixelsPerPoint
        )
        guard let cropped = variant.cropping(to: pixelRect) else { return }
        NSImage(cgImage: cropped, size: rect.size).draw(in: rect)
    }

    // MARK: - Export

    public func renderFinalImage() -> CGImage? {
        commitTextEntry()

        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let pixelsPerPoint = CGFloat(width) / canvasSize.width
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previous }

        NSImage(cgImage: baseImage, size: canvasSize).draw(in: NSRect(origin: .zero, size: canvasSize))
        for shape in shapes {
            drawShape(shape) // selection chrome intentionally not rendered
        }

        return context.makeImage()
    }
}

extension EditorCanvasView: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEntry()
    }
}
