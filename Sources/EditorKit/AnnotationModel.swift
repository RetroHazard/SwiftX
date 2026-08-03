// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Annotation model for the image editor. Tool set mirrors the core of
// ShareX.ImageEditor/Core/Annotations. Emoji stamps are covered by the text
// tool + the macOS emoji palette; cursor stamps are N/A (captures already
// include the cursor).

import AppKit
import SharedKit

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
        case .select: return L10n.t("editor.tool.select")
        case .rectangle: return L10n.t("editor.tool.rectangle")
        case .ellipse: return L10n.t("editor.tool.ellipse")
        case .line: return L10n.t("editor.tool.line")
        case .arrow: return L10n.t("editor.tool.arrow")
        case .freehand: return L10n.t("editor.tool.freehand")
        case .text: return L10n.t("editor.tool.text")
        case .speechBalloon: return L10n.t("editor.tool.speech_balloon")
        case .step: return L10n.t("editor.tool.step")
        case .magnify: return L10n.t("editor.tool.magnify")
        case .blur: return L10n.t("editor.tool.blur")
        case .pixelate: return L10n.t("editor.tool.pixelate")
        case .highlight: return L10n.t("editor.tool.highlight")
        case .smartEraser: return L10n.t("editor.tool.smart_eraser")
        case .spotlight: return L10n.t("editor.tool.spotlight")
        case .image: return L10n.t("editor.tool.image")
        case .crop: return L10n.t("editor.tool.crop")
        case .cutOut: return L10n.t("editor.tool.cut_out")
        }
    }

    /// Tools placed with a single click rather than a drag.
    public var isClickPlaced: Bool {
        self == .text || self == .step || self == .image
    }

    /// Annotation shapes that honor the drop-shadow style. Effect regions,
    /// modes and the balloon (which draws its own body) are excluded.
    public var castsShadow: Bool {
        switch self {
        case .rectangle, .ellipse, .line, .arrow, .freehand, .text, .step, .image:
            return true
        default:
            return false
        }
    }
}

/// Upstream v21 arrow style: Classic is the filled triangle head, Modern is
/// an open chevron stroked at the line width.
public enum ArrowHeadStyle: String, CaseIterable, Sendable {
    case classic = "Classic"
    case modern = "Modern"

    /// Localized display label; the rawValue stays the stable identifier.
    public var localizedName: String {
        switch self {
        case .classic: return L10n.t("editor.arrow_style.classic")
        case .modern: return L10n.t("editor.arrow_style.modern")
        }
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
    /// Interior fill for rectangle/ellipse; alpha 0 means no fill (C# default).
    public var fillColor: NSColor = .clear
    public var shadow = false
    public var lineWidth: CGFloat = 3
    public var fontSize: CGFloat = 18
    /// Font family for text/speech-balloon; empty = system font (upstream v20.1 option).
    public var fontFamily: String = ""
    public var arrowStyle: ArrowHeadStyle = .classic
    /// Stamp content for the image tool (CGImages are immutable, copies are cheap).
    public var stampImage: CGImage?

    public init(tool: AnnotationTool) {
        self.tool = tool
    }
}
