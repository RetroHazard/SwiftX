// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Annotation model for the image editor. Tool set mirrors the core of
// ShareX.ImageEditor/Core/Annotations. Emoji stamps are covered by the text
// tool + the macOS emoji palette; cursor stamps are N/A (captures already
// include the cursor).

import AppKit

public enum AnnotationTool: String, CaseIterable, Identifiable {
    /// Selection/manipulation mode - never stored on a shape.
    case select
    case rectangle
    case ellipse
    case line
    case arrow
    case freehand
    case text
    case speechBalloon
    case step
    case magnify
    case blur
    case pixelate
    case highlight
    case smartEraser
    case spotlight
    case image
    /// Crops the base image - a mode like select, never stored as a shape.
    case crop
    /// Removes a full-width or full-height band - a mode, never stored.
    case cutOut

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .freehand: return "scribble"
        case .text: return "textformat"
        case .speechBalloon: return "bubble.left"
        case .step: return "1.circle"
        case .magnify: return "plus.magnifyingglass"
        case .blur: return "drop"
        case .pixelate: return "squareshape.split.3x3"
        case .highlight: return "highlighter"
        case .smartEraser: return "eraser"
        case .spotlight: return "flashlight.on.fill"
        case .image: return "photo"
        case .crop: return "crop"
        case .cutOut: return "scissors"
        }
    }

    public var displayName: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .freehand: return "Freehand"
        case .text: return "Text"
        case .speechBalloon: return "Speech balloon"
        case .step: return "Step number"
        case .magnify: return "Magnify"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .highlight: return "Highlight"
        case .smartEraser: return "Smart eraser"
        case .spotlight: return "Spotlight"
        case .image: return "Image stamp"
        case .crop: return "Crop"
        case .cutOut: return "Cut out"
        }
    }

    /// Tools placed with a single click rather than a drag.
    public var isClickPlaced: Bool {
        self == .text || self == .step || self == .image
    }
}

public struct AnnotationShape: Identifiable {
    public var id = UUID()
    public var tool: AnnotationTool
    /// Normalized rect in canvas coordinates (top-left origin).
    public var rect: CGRect = .zero
    /// Start/end for line/arrow; full path for freehand.
    public var points: [CGPoint] = []
    public var text: String = ""
    public var number: Int = 0
    public var color: NSColor = .systemRed
    public var lineWidth: CGFloat = 3
    public var fontSize: CGFloat = 18
    /// Stamp content for the image tool (CGImages are immutable, copies are cheap).
    public var stampImage: CGImage?

    public init(tool: AnnotationTool) {
        self.tool = tool
    }
}
