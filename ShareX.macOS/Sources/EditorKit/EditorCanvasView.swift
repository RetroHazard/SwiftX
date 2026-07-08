// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Annotation canvas: displays the image at screen scale, handles tool input,
// keeps undo/redo history, and renders the final image at full pixel size.
// The same drawShapes routine draws both the live view and the export, so
// preview and output cannot drift apart.

import AppKit
import CoreImage

@MainActor
public final class EditorCanvasView: NSView {
    public let baseImage: CGImage
    public var currentTool: AnnotationTool = .rectangle
    public var currentColor: NSColor = .systemRed
    public var currentLineWidth: CGFloat = 3
    public var onHistoryChanged: (() -> Void)?

    private(set) var shapes: [AnnotationShape] = []
    private var redoShapes: [AnnotationShape] = []
    private var draft: AnnotationShape?
    private var dragStart: CGPoint = .zero
    private var activeTextField: NSTextField?

    public var canUndo: Bool { !shapes.isEmpty }
    public var canRedo: Bool { !redoShapes.isEmpty }

    public init(image: CGImage) {
        self.baseImage = image
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        super.init(frame: NSRect(origin: .zero, size: size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Effect variants (blur/pixelate draw regions from these)

    private lazy var blurredBase: CGImage? = {
        let input = CIImage(cgImage: baseImage)
        guard let filter = CIFilter(name: "CIGaussianBlur", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputRadiusKey: 12.0
        ]), let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }()

    private lazy var pixelatedBase: CGImage? = {
        let input = CIImage(cgImage: baseImage)
        guard let filter = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: input.clampedToExtent(),
            kCIInputScaleKey: max(8.0, Double(baseImage.width) / 80.0),
            kCIInputCenterKey: CIVector(x: 0, y: 0)
        ]), let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }()

    // MARK: - History

    public func addShape(_ shape: AnnotationShape) {
        shapes.append(shape)
        redoShapes.removeAll()
        needsDisplay = true
        onHistoryChanged?()
    }

    public func undo() {
        guard let last = shapes.popLast() else { return }
        redoShapes.append(last)
        needsDisplay = true
        onHistoryChanged?()
    }

    public func redo() {
        guard let last = redoShapes.popLast() else { return }
        shapes.append(last)
        needsDisplay = true
        onHistoryChanged?()
    }

    // MARK: - Input

    public override func mouseDown(with event: NSEvent) {
        commitTextEntry()
        let point = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            beginTextEntry(at: point)
            return
        }
        if currentTool == .step {
            var shape = AnnotationShape(tool: .step)
            let nextNumber = (shapes.filter { $0.tool == .step }.map(\.number).max() ?? 0) + 1
            shape.number = nextNumber
            shape.rect = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
            shape.color = currentColor
            addShape(shape)
            return
        }

        dragStart = point
        var shape = AnnotationShape(tool: currentTool)
        shape.color = currentColor
        shape.lineWidth = currentLineWidth
        shape.points = [point, point]
        draft = shape
    }

    public override func mouseDragged(with event: NSEvent) {
        guard var shape = draft else { return }
        let point = convert(event.locationInWindow, from: nil)

        switch shape.tool {
        case .freehand:
            shape.points.append(point)
        case .line, .arrow:
            shape.points = [dragStart, point]
        default:
            shape.rect = CGRect(
                x: min(dragStart.x, point.x),
                y: min(dragStart.y, point.y),
                width: abs(point.x - dragStart.x),
                height: abs(point.y - dragStart.y)
            )
        }
        draft = shape
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        guard let shape = draft else { return }
        draft = nil
        let point = convert(event.locationInWindow, from: nil)
        let dragDistance = hypot(point.x - dragStart.x, point.y - dragStart.y)
        guard dragDistance >= 3 || shape.tool == .freehand else {
            needsDisplay = true
            return
        }
        addShape(shape)
    }

    // MARK: - Text entry

    private func beginTextEntry(at point: CGPoint) {
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y, width: 240, height: 26))
        field.font = .systemFont(ofSize: 18)
        field.textColor = currentColor
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
        let origin = field.frame.origin
        field.removeFromSuperview()
        guard !text.isEmpty else { return }

        var shape = AnnotationShape(tool: .text)
        shape.text = text
        shape.rect = CGRect(origin: origin, size: .zero)
        shape.color = currentColor
        addShape(shape)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: baseImage, size: bounds.size).draw(in: bounds)
        for shape in shapes {
            drawShape(shape)
        }
        if let draft {
            drawShape(draft)
        }
    }

    private func drawShape(_ shape: AnnotationShape) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        shape.color.setStroke()
        shape.color.setFill()

        switch shape.tool {
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
        let pixelsPerPoint = CGFloat(baseImage.width) / bounds.width
        // variant is in image pixel space with bottom-left origin; our rect is top-left
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

        // flip to top-left origin and scale from view points to image pixels,
        // then reuse the exact drawing routines the live view uses
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        let pixelsPerPoint = CGFloat(width) / bounds.width
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: true)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext
        defer { NSGraphicsContext.current = previous }

        NSImage(cgImage: baseImage, size: bounds.size).draw(in: NSRect(origin: .zero, size: bounds.size))
        for shape in shapes {
            drawShape(shape)
        }

        return context.makeImage()
    }
}

extension EditorCanvasView: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ notification: Notification) {
        commitTextEntry()
    }
}
