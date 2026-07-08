// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

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
