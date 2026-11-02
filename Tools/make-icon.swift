#!/usr/bin/env swift
// Renders Sweep's app icon into an .appiconset folder.
//
//     swift Tools/make-icon.swift Sweep/Resources/Assets.xcassets/AppIcon.appiconset
//
// The artwork follows Apple's macOS icon grid: an 824 pt rounded square centered
// on a 1024 pt canvas, with room for the drop shadow.

import AppKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

/// Draws the icon at 1024×1024 and returns it scaled to `pixels`.
func renderIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Soft drop shadow under the tile.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35).cgColor)
    color(0.55, 0.33, 0.95).setFill()
    bodyPath.fill()
    cg.restoreGState()

    // Purple to pink diagonal gradient, the Smart Scan colors.
    cg.saveGState()
    bodyPath.addClip()
    NSGradient(colors: [color(0.47, 0.30, 0.98), color(0.70, 0.32, 0.88), color(0.96, 0.38, 0.60)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: body, angle: -45)

    // Gentle light from the top for depth.
    NSGradient(colors: [color(1, 1, 1, 0.28), color(1, 1, 1, 0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)

    // A sweeping arc behind the sparkles.
    let arc = NSBezierPath()
    arc.appendArc(withCenter: CGPoint(x: 512, y: 470), radius: 300, startAngle: 200, endAngle: 340, clockwise: false)
    arc.lineWidth = 34
    arc.lineCapStyle = .round
    color(1, 1, 1, 0.35).setStroke()
    arc.stroke()
    cg.restoreGState()

    // White sparkles glyph with a subtle shadow.
    let configuration = NSImage.SymbolConfiguration(pointSize: 430, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let size = symbol.size
        let origin = CGPoint(x: 512 - size.width / 2, y: 540 - size.height / 2)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0.25, 0.05, 0.35, 0.45).cgColor)
        symbol.draw(in: CGRect(origin: origin, size: size))
        cg.restoreGState()
    }

    // Hairline edge so the tile reads on light backgrounds.
    color(1, 1, 1, 0.22).setStroke()
    let edge = NSBezierPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    edge.lineWidth = 3
    edge.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

struct Variant {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let variants = [16, 32, 128, 256, 512].flatMap { [Variant(points: $0, scale: 1), Variant(points: $0, scale: 2)] }

try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
for variant in variants {
    let data = renderIcon(pixels: variant.pixels).representation(using: .png, properties: [:])!
    try data.write(to: outputFolder.appendingPathComponent(variant.filename))
}

let images = variants.map { variant in
    """
        { "filename" : "\(variant.filename)", "idiom" : "mac", "scale" : "\(variant.scale)x", "size" : "\(variant.points)x\(variant.points)" }
    """
}
let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: outputFolder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(variants.count) icons to \(outputFolder.path)")
