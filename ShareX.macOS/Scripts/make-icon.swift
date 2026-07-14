#!/usr/bin/env swift
// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Generates the SwiftX app icon: a camera aperture (nod to the ShareX logo)
// with a swift in flight (nod to the Swift language) inside the opening.
// Pure CoreGraphics — rerun to regenerate Resources/SwiftX.icns at any size.
//
// Usage: swift Scripts/make-icon.swift   (from the ShareX.macOS directory)

import AppKit

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

/// Swift-in-flight silhouette in unit space (y up, facing right, ~2×1.5 units):
/// pointed beak, swept-back wing above, forked swallow tail behind.
func birdPath() -> CGPath {
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

func render(_ pixels: Int) -> CGImage {
    let S = CGFloat(pixels)
    let ctx = CGContext(data: nil, width: pixels, height: pixels,
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let center = CGPoint(x: S / 2, y: S / 2)

    // Squircle background — macOS icon grid: 824/1024 with ~185 corner radius
    let inset = 0.0977 * S
    let bg = CGPath(roundedRect: CGRect(x: inset, y: inset,
                                        width: S - 2 * inset, height: S - 2 * inset),
                    cornerWidth: 0.181 * S, cornerHeight: 0.181 * S, transform: nil)
    ctx.addPath(bg)
    ctx.clip()
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: nil,
                   colors: [srgb(0x2A3646), srgb(0x11161D)] as CFArray,
                   locations: [0, 1])!,
        start: CGPoint(x: center.x, y: S - inset),
        end: CGPoint(x: center.x, y: inset), options: [])

    // Lens ring framing the iris
    let ringRadius = 0.335 * S
    ctx.setStrokeColor(srgb(0xB8CCDF, 0.45))
    ctx.setLineWidth(0.016 * S)
    ctx.strokeEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius,
                                 width: 2 * ringRadius, height: 2 * ringRadius))

    // Aperture: each blade is a hexagon side extended outward to the ring.
    let r = 0.225 * S            // iris opening (hexagon vertex radius)
    let R = ringRadius - 0.045 * S   // stop short so round caps stay inside the ring
    ctx.setStrokeColor(srgb(0xB8CCDF))
    ctx.setLineWidth(0.052 * S)
    ctx.setLineCap(.round)
    let tilt = CGFloat.pi / 12   // keep blades off the axes so the X reads
    for k in 0..<6 {
        let a1 = CGFloat(k) * .pi / 3 + tilt
        let a2 = a1 + .pi / 3
        let u = CGPoint(x: r * cos(a1), y: r * sin(a1))    // vertex, center-relative
        let d = CGPoint(x: r * cos(a2) - u.x, y: r * sin(a2) - u.y)
        // solve |u + t·d| = R for the far endpoint (t > 1 root)
        let dd = d.x * d.x + d.y * d.y
        let ud = u.x * d.x + u.y * d.y
        let t = (-ud + sqrt(ud * ud - dd * (r * r - R * R))) / dd
        ctx.move(to: CGPoint(x: center.x + u.x, y: center.y + u.y))
        ctx.addLine(to: CGPoint(x: center.x + u.x + t * d.x, y: center.y + u.y + t * d.y))
        ctx.strokePath()
    }

    // Swift-orange bird in the opening
    let scale = 0.17 * S
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
        .scaledBy(x: scale, y: scale)
    let bird = birdPath().copy(using: &transform)!
    ctx.saveGState()
    ctx.addPath(bird)
    ctx.clip()
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: nil,
                   colors: [srgb(0xFF9A5A), srgb(0xF05138)] as CFArray,
                   locations: [0, 1])!,
        start: CGPoint(x: center.x, y: center.y + scale),
        end: CGPoint(x: center.x, y: center.y - scale), options: [])
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/SwiftX.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                        (256, 1), (256, 2), (512, 1), (512, 2)] {
    let suffix = scale == 2 ? "@2x" : ""
    try writePNG(render(points * scale),
                 to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}

try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", "Resources/SwiftX.icns", iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

// Standalone PNG set for documentation, packaging, and the website.
// 180 = apple-touch-icon, 192/512 = web manifest, rest are the classic ladder.
let assets = URL(fileURLWithPath: "Assets/icons")
try fm.createDirectory(at: assets, withIntermediateDirectories: true)
for size in [16, 32, 48, 64, 128, 180, 192, 256, 512, 1024] {
    try writePNG(render(size), to: assets.appendingPathComponent("swiftx-\(size).png"))
}

try writePNG(render(512), to: URL(fileURLWithPath: "build/icon-preview.png"))
print("Wrote Resources/SwiftX.icns, Assets/icons/swiftx-{16...1024}.png (preview: build/icon-preview.png)")
