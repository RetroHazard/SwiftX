// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit

/// Monochrome template rendering of the SwiftX mark (aperture blades with the
/// swift in the opening) for the status bar. The menu bar tints template
/// images for light/dark/selected states, so this draws in plain black.
/// Geometry mirrors Scripts/make-icon.swift — keep the two in sync.
enum StatusIcon {
    static let idle: NSImage = {
        // drawingHandler re-runs per backing scale, so it stays crisp on retina
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx, size: rect.width)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SwiftX"
        return image
    }()

    private static func draw(in ctx: CGContext, size S: CGFloat) {
        let center = CGPoint(x: S / 2, y: S / 2)
        ctx.setStrokeColor(.black)
        ctx.setFillColor(.black)

        // Aperture blades: hexagon sides extended outward, as in the app icon,
        // but no lens ring — its stroke would be sub-pixel at menu bar size.
        let r = 0.30 * S             // iris opening (hexagon vertex radius)
        let R = 0.48 * S             // blade outer end
        ctx.setLineWidth(0.085 * S)
        ctx.setLineCap(.round)
        let tilt = CGFloat.pi / 12   // keep blades off the axes so the X reads
        for k in 0..<6 {
            let a1 = CGFloat(k) * .pi / 3 + tilt
            let a2 = a1 + .pi / 3
            let u = CGPoint(x: r * cos(a1), y: r * sin(a1))
            let d = CGPoint(x: r * cos(a2) - u.x, y: r * sin(a2) - u.y)
            // solve |u + t·d| = R for the far endpoint (t > 1 root)
            let dd = d.x * d.x + d.y * d.y
            let ud = u.x * d.x + u.y * d.y
            let t = (-ud + sqrt(ud * ud - dd * (r * r - R * R))) / dd
            ctx.move(to: CGPoint(x: center.x + u.x, y: center.y + u.y))
            ctx.addLine(to: CGPoint(x: center.x + u.x + t * d.x, y: center.y + u.y + t * d.y))
            ctx.strokePath()
        }

        // Swift silhouette in the opening
        let scale = 0.22 * S
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: scale)
        ctx.addPath(birdPath().copy(using: &transform)!)
        ctx.fillPath()
    }

    /// Swift-in-flight silhouette in unit space (y up, facing right, ~2×1.5 units):
    /// pointed beak, swept-back wing above, forked swallow tail behind.
    private static func birdPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 1.00, y: 0.10))                                   // beak
        path.addQuadCurve(to: CGPoint(x: 0.45, y: 0.34),
                          control: CGPoint(x: 0.80, y: 0.32))                      // head
        path.addQuadCurve(to: CGPoint(x: 0.05, y: 0.30),
                          control: CGPoint(x: 0.25, y: 0.28))                      // back
        path.addCurve(to: CGPoint(x: -0.75, y: 0.95),
                      control1: CGPoint(x: -0.20, y: 0.42),
                      control2: CGPoint(x: -0.50, y: 0.80))                        // wing leading edge
        path.addCurve(to: CGPoint(x: -0.05, y: 0.02),
                      control1: CGPoint(x: -0.60, y: 0.62),
                      control2: CGPoint(x: -0.35, y: 0.20))                        // wing underside
        path.addQuadCurve(to: CGPoint(x: -0.90, y: -0.25),
                          control: CGPoint(x: -0.45, y: -0.05))                    // tail, upper streamer
        path.addQuadCurve(to: CGPoint(x: -0.55, y: -0.28),
                          control: CGPoint(x: -0.70, y: -0.28))                    // fork notch
        path.addQuadCurve(to: CGPoint(x: -0.80, y: -0.55),
                          control: CGPoint(x: -0.68, y: -0.40))                    // tail, lower streamer
        path.addCurve(to: CGPoint(x: 1.00, y: 0.10),
                      control1: CGPoint(x: -0.20, y: -0.35),
                      control2: CGPoint(x: 0.55, y: -0.28))                        // belly
        path.closeSubpath()
        return path
    }
}
