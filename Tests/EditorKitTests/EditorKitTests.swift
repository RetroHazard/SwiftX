// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import AppKit
import Testing
@testable import EditorKit

@MainActor
struct EditorKitTests {
    private func makeImage(width: Int = 100, height: Int = 100, red: CGFloat = 1) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let data = image.dataProvider!.data! as Data
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * image.bytesPerRow + x * bytesPerPixel
        return (data[offset], data[offset + 1], data[offset + 2])
    }

    @Test func undoRedoStack() {
        let canvas = EditorCanvasView(image: makeImage())
        #expect(!canvas.canUndo)
        canvas.addShape(AnnotationShape(tool: .rectangle))
        canvas.addShape(AnnotationShape(tool: .ellipse))
        #expect(canvas.canUndo)
        #expect(!canvas.canRedo)

        canvas.undo()
        #expect(canvas.canRedo)
        #expect(canvas.shapes.count == 1)
        canvas.redo()
        #expect(canvas.shapes.count == 2)

        // new shape clears redo
        canvas.undo()
        canvas.addShape(AnnotationShape(tool: .line))
        #expect(!canvas.canRedo)
    }

    @Test func hitTestingFindsTopmostShape() {
        let canvas = EditorCanvasView(image: makeImage())
        let w = canvas.bounds.width, h = canvas.bounds.height

        var bottom = AnnotationShape(tool: .rectangle)
        bottom.rect = CGRect(x: 0, y: 0, width: w * 0.8, height: h * 0.8)
        canvas.addShape(bottom)

        var top = AnnotationShape(tool: .ellipse)
        top.rect = CGRect(x: w * 0.1, y: h * 0.1, width: w * 0.3, height: h * 0.3)
        canvas.addShape(top)

        // point inside both -> topmost (ellipse, added last) wins
        let inside = CGPoint(x: w * 0.2, y: h * 0.2)
        #expect(canvas.shapeIndex(at: inside) == 1)
        // point only inside the rectangle
        #expect(canvas.shapeIndex(at: CGPoint(x: w * 0.7, y: h * 0.7)) == 0)
        // point outside everything
        #expect(canvas.shapeIndex(at: CGPoint(x: w * 0.95, y: h * 0.95)) == nil)
    }

    @Test func lineHitTestUsesSegmentDistance() {
        let canvas = EditorCanvasView(image: makeImage())
        let w = canvas.bounds.width, h = canvas.bounds.height
        var line = AnnotationShape(tool: .line)
        line.points = [CGPoint(x: 0, y: 0), CGPoint(x: w, y: h)]
        canvas.addShape(line)

        #expect(canvas.shapeIndex(at: CGPoint(x: w * 0.5, y: h * 0.5)) == 0) // on the line
        #expect(canvas.shapeIndex(at: CGPoint(x: w * 0.8, y: h * 0.2)) == nil) // far off it
    }

    @Test func moveTranslatesRectAndPoints() {
        let canvas = EditorCanvasView(image: makeImage())
        var arrow = AnnotationShape(tool: .arrow)
        arrow.points = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)]
        let moved = canvas.translated(arrow, by: CGPoint(x: 5, y: -3))
        #expect(moved.points == [CGPoint(x: 15, y: 7), CGPoint(x: 35, y: 17)])

        var rect = AnnotationShape(tool: .rectangle)
        rect.rect = CGRect(x: 10, y: 10, width: 20, height: 20)
        let movedRect = canvas.translated(rect, by: CGPoint(x: -5, y: 5))
        #expect(movedRect.rect == CGRect(x: 5, y: 15, width: 20, height: 20))
    }

    @Test func resizeFromCornerAnchorsOpposite() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .rectangle)
        shape.rect = CGRect(x: 10, y: 10, width: 20, height: 20)
        // handle 0 = top-left; anchor = bottom-right (30,30); drag to (0,0)
        let resized = canvas.resized(shape, handle: 0, to: CGPoint(x: 0, y: 0))
        #expect(resized.rect == CGRect(x: 0, y: 0, width: 30, height: 30))

        // line endpoint drag
        var line = AnnotationShape(tool: .line)
        line.points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let stretched = canvas.resized(line, handle: 1, to: CGPoint(x: 50, y: 5))
        #expect(stretched.points[1] == CGPoint(x: 50, y: 5))
        #expect(stretched.points[0] == CGPoint(x: 0, y: 0))
    }

    @Test func deleteSelectedShapeIsUndoable() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .rectangle)
        shape.rect = CGRect(x: 1, y: 1, width: 5, height: 5)
        canvas.addShape(shape)
        #expect(canvas.selectedShapeID == shape.id) // auto-selected after draw

        canvas.deleteSelectedShape()
        #expect(canvas.shapes.isEmpty)
        #expect(canvas.selectedShapeID == nil)

        canvas.undo()
        #expect(canvas.shapes.count == 1)
    }

    @Test func colorChangeAppliesToSelectionAndIsUndoable() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .rectangle)
        shape.color = .systemRed
        canvas.addShape(shape)

        canvas.setColor(.systemBlue)
        #expect(canvas.shapes[0].color == .systemBlue)

        // repeated set with the same color must not add history entries
        let undoDepth = 2 // add + recolor
        canvas.setColor(.systemBlue)
        canvas.undo()
        #expect(canvas.shapes[0].color == .systemRed)
        _ = undoDepth

        // without selection, color only changes the tool default
        canvas.selectShape(id: nil)
        canvas.setColor(.systemGreen)
        #expect(canvas.shapes[0].color == .systemRed)
        #expect(canvas.currentColor == .systemGreen)
    }

    @Test func speechBalloonTailIsFifthHandle() {
        let canvas = EditorCanvasView(image: makeImage())
        var balloon = AnnotationShape(tool: .speechBalloon)
        balloon.rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        balloon.points = [CGPoint(x: 15, y: 45)] // tail tip
        canvas.addShape(balloon)

        // handle index 4 moves the tail without touching the body
        let resized = canvas.resized(balloon, handle: 4, to: CGPoint(x: 40, y: 5))
        #expect(resized.points == [CGPoint(x: 40, y: 5)])
        #expect(resized.rect == balloon.rect)

        // corner handle still resizes the body
        let bodyResized = canvas.resized(balloon, handle: 0, to: CGPoint(x: 0, y: 0))
        #expect(bodyResized.rect == CGRect(x: 0, y: 0, width: 40, height: 30))
    }

    @Test func speechBalloonMovesTailWithBody() {
        let canvas = EditorCanvasView(image: makeImage())
        var balloon = AnnotationShape(tool: .speechBalloon)
        balloon.rect = CGRect(x: 10, y: 10, width: 30, height: 20)
        balloon.points = [CGPoint(x: 15, y: 45)]
        let moved = canvas.translated(balloon, by: CGPoint(x: 5, y: 5))
        #expect(moved.rect.origin == CGPoint(x: 15, y: 15))
        #expect(moved.points == [CGPoint(x: 20, y: 50)])
    }

    @Test func cropShrinksImageAndTranslatesShapes() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        var shape = AnnotationShape(tool: .rectangle)
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        shape.rect = CGRect(x: w * 0.5, y: h * 0.5, width: w * 0.2, height: h * 0.2)
        canvas.addShape(shape)

        // crop away the left/top quarter
        canvas.applyCrop(CGRect(x: w * 0.25, y: h * 0.25, width: w * 0.75, height: h * 0.75))

        #expect(canvas.baseImage.width == 75)
        #expect(canvas.baseImage.height == 75)
        #expect(canvas.canvasSize.width == w * 0.75)
        // shape moved with the image content
        #expect(abs(canvas.shapes[0].rect.minX - w * 0.25) < 0.5)
    }

    @Test func cropIsUndoable() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        canvas.applyCrop(CGRect(x: 0, y: 0, width: w * 0.5, height: h * 0.5))
        #expect(canvas.baseImage.width == 50)

        canvas.undo()
        #expect(canvas.baseImage.width == 100)
        #expect(canvas.canvasSize.width == w)

        canvas.redo()
        #expect(canvas.baseImage.width == 50)
    }

    @Test func tinyCropIsIgnored() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        canvas.applyCrop(CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(canvas.baseImage.width == 100)
        #expect(!canvas.canUndo) // no history entry for a no-op
    }

    @Test func renderWithoutShapesMatchesBase() {
        let canvas = EditorCanvasView(image: makeImage())
        let rendered = canvas.renderFinalImage()!
        #expect(rendered.width == 100)
        #expect(rendered.height == 100)
        let p = pixel(rendered, x: 50, y: 50)
        // NSImage drawing color-matches between spaces, so allow drift; still clearly red
        #expect(p.r > 200 && p.g < 80 && p.b < 80)
    }

    @Test func renderedShapeChangesPixels() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .rectangle)
        // canvas bounds are pixels/scale; use fractions of bounds to be scale-proof
        let w = canvas.bounds.width, h = canvas.bounds.height
        shape.rect = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6)
        shape.color = .blue
        shape.lineWidth = 6
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        // sample on the stroke (top edge at 20% height): should be blue-ish, not red
        let edge = pixel(rendered, x: 50, y: 20)
        #expect(edge.b > 100)
        #expect(edge.r < 150)
        // center untouched
        let center = pixel(rendered, x: 50, y: 50)
        #expect(center.r > 240)
    }

    @Test func blurRegionAltersOnlyItsArea() {
        // base with a sharp black/white boundary so blur visibly changes pixels
        let width = 100, height = 100
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(.black)
        for stripe in stride(from: 0, to: width, by: 4) {
            context.fill(CGRect(x: stripe, y: 0, width: 2, height: height))
        }
        let striped = context.makeImage()!

        let canvas = EditorCanvasView(image: striped)
        var shape = AnnotationShape(tool: .blur)
        let w = canvas.bounds.width, h = canvas.bounds.height
        shape.rect = CGRect(x: 0, y: 0, width: w * 0.5, height: h * 0.5)
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        // inside the blur region stripes should smear to gray
        let inside = pixel(rendered, x: 10, y: 10)
        #expect(inside.r > 40 && inside.r < 215)
        // outside region keeps hard stripes: sample a known white column
        let outside = pixel(rendered, x: 75, y: 75)
        #expect(outside.r > 215 || outside.r < 40)
    }

    private func makeSplitImage(width: Int = 100, height: Int = 100) -> CGImage {
        // left half red, right half blue
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    @Test func smartEraserSamplesBaseColor() {
        let canvas = EditorCanvasView(image: makeSplitImage())
        let w = canvas.canvasSize.width
        let left = canvas.baseColor(at: CGPoint(x: w * 0.25, y: canvas.canvasSize.height / 2))
        let right = canvas.baseColor(at: CGPoint(x: w * 0.75, y: canvas.canvasSize.height / 2))
        #expect(left.redComponent > 0.8 && left.blueComponent < 0.2)
        #expect(right.blueComponent > 0.8 && right.redComponent < 0.2)
    }

    @Test func cutOutRemovesColumnsAndCollapsesShapes() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height

        var shape = AnnotationShape(tool: .rectangle)
        shape.rect = CGRect(x: w * 0.8, y: h * 0.2, width: w * 0.1, height: h * 0.1)
        canvas.addShape(shape)

        // wider than tall -> removes the column band [0.3w, 0.5w) at full height
        canvas.applyCutOut(CGRect(x: w * 0.3, y: h * 0.4, width: w * 0.2, height: h * 0.05))

        #expect(canvas.baseImage.width == 80)
        #expect(canvas.baseImage.height == 100)
        // shape beyond the band moved left by the band width
        #expect(abs(canvas.shapes[0].rect.minX - w * 0.6) < 0.5)

        canvas.undo()
        #expect(canvas.baseImage.width == 100)
        #expect(abs(canvas.shapes[0].rect.minX - w * 0.8) < 0.5)
    }

    @Test func cutOutRemovesRows() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        // taller than wide -> removes the row band at full width
        canvas.applyCutOut(CGRect(x: w * 0.4, y: h * 0.25, width: w * 0.05, height: h * 0.5))
        #expect(canvas.baseImage.width == 100)
        #expect(canvas.baseImage.height == 50)
    }

    @Test func cutOutFullSpanIsIgnored() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        canvas.applyCutOut(CGRect(x: 0, y: h * 0.4, width: w, height: h * 0.1))
        #expect(canvas.baseImage.width == 100)
        #expect(!canvas.canUndo)
    }

    @Test func spotlightDimsOutsideItsRegion() {
        let canvas = EditorCanvasView(image: makeImage()) // all red
        var shape = AnnotationShape(tool: .spotlight)
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        shape.rect = CGRect(x: w * 0.3, y: h * 0.3, width: w * 0.4, height: h * 0.4)
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        let inside = pixel(rendered, x: 50, y: 50)
        let outside = pixel(rendered, x: 5, y: 5)
        #expect(inside.r > 200)          // spotlit area untouched
        #expect(outside.r < inside.r / 2) // dimmed area clearly darker
    }

    @Test func imageStampRendersInItsRect() {
        let canvas = EditorCanvasView(image: makeImage()) // red base
        var shape = AnnotationShape(tool: .image)
        shape.stampImage = makeImage(width: 10, height: 10, red: 0) // black stamp
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        shape.rect = CGRect(x: w * 0.4, y: h * 0.4, width: w * 0.2, height: h * 0.2)
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        #expect(pixel(rendered, x: 50, y: 50).r < 60)  // stamp covers center
        #expect(pixel(rendered, x: 10, y: 10).r > 200) // base visible elsewhere
    }

    @Test func expandCanvasGrowsImageAndTranslatesShapes() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let pixelsPerPoint = CGFloat(100) / canvas.canvasSize.width

        var shape = AnnotationShape(tool: .rectangle)
        shape.rect = CGRect(x: 10, y: 10, width: 5, height: 5)
        canvas.addShape(shape)

        canvas.expandCanvas(top: 10, left: 20, bottom: 0, right: 0, color: .white)
        #expect(canvas.baseImage.width == 100 + Int(20 * pixelsPerPoint))
        #expect(canvas.baseImage.height == 100 + Int(10 * pixelsPerPoint))
        #expect(canvas.shapes[0].rect.origin == CGPoint(x: 30, y: 20))

        // padding is white, original content starts after it
        let rendered = canvas.renderFinalImage()!
        let pad = pixel(rendered, x: 2, y: rendered.height - 2)
        #expect(pad.r > 240 && pad.g > 240 && pad.b > 240)

        canvas.undo()
        #expect(canvas.baseImage.width == 100)
        #expect(canvas.shapes[0].rect.origin == CGPoint(x: 10, y: 10))
    }

    @Test func zoomClampsAndScalesDisplaySize() {
        let canvas = EditorCanvasView(image: makeImage(width: 100, height: 100))
        let base = canvas.canvasSize
        canvas.setZoom(2)
        #expect(canvas.displaySize == NSSize(width: base.width * 2, height: base.height * 2))
        canvas.setZoom(100)
        #expect(canvas.zoom == 4) // clamped
        canvas.setZoom(0.01)
        #expect(canvas.zoom == 0.25)
        // zoom is a view transform only - canvas geometry untouched
        #expect(canvas.canvasSize == base)
    }

    @Test func fillColorRendersInsideRectangle() {
        let canvas = EditorCanvasView(image: makeImage()) // red base
        var shape = AnnotationShape(tool: .rectangle)
        let w = canvas.canvasSize.width, h = canvas.canvasSize.height
        shape.rect = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6)
        shape.color = .black
        shape.fillColor = .systemBlue
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        let center = pixel(rendered, x: 50, y: 50)
        #expect(center.b > 150 && center.r < 150) // filled blue, not base red
    }

    @Test func fillAndShadowApplyToSelectionAndAreUndoable() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .ellipse)
        shape.rect = CGRect(x: 10, y: 10, width: 30, height: 30)
        canvas.addShape(shape) // auto-selected

        canvas.setFillColor(.systemGreen)
        canvas.setShadow(true)
        #expect(canvas.shapes[0].fillColor == .systemGreen)
        #expect(canvas.shapes[0].shadow)

        canvas.undo() // shadow
        #expect(!canvas.shapes[0].shadow)
        canvas.undo() // fill
        #expect(canvas.shapes[0].fillColor.alphaComponent == 0)

        // with nothing selected only the tool defaults change
        canvas.selectShape(id: nil)
        canvas.setShadow(false)
        canvas.setShadow(true)
        #expect(!canvas.shapes[0].shadow)
        #expect(canvas.currentShadow)
    }

    @Test func stepNumbersRenderFilledCircle() {
        let canvas = EditorCanvasView(image: makeImage())
        var shape = AnnotationShape(tool: .step)
        shape.number = 1
        let w = canvas.bounds.width, h = canvas.bounds.height
        shape.rect = CGRect(x: w * 0.4, y: h * 0.4, width: w * 0.2, height: h * 0.2)
        shape.color = .blue
        canvas.addShape(shape)

        let rendered = canvas.renderFinalImage()!
        let center = pixel(rendered, x: 50, y: 52) // inside circle, below the numeral
        #expect(center.b > 100 || (center.r > 200 && center.g > 200)) // blue fill or white numeral
    }
}
