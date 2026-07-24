#!/usr/bin/env swift

import AppKit
import Foundation

// Geometry matches the macOS 26 icon grid, measured from the system icons:
// the opaque shape is 814x814 inside a 1024 canvas (105 inset on every side),
// and its straight edges begin 176pt from each corner. The remaining canvas
// holds the soft ambient shadow.
private enum IconMetrics {
    static let canvas: CGFloat = 1024
    static let shapeInset: CGFloat = 105
    /// How far the corner reaches along each edge before the edge runs straight.
    /// Together with the smoothing below this reproduces the measured system
    /// corner to within ~2pt at 1024, sweeping both values against it.
    static let cornerExtent: CGFloat = 206
    /// Continuous-curvature amount. 0 is a plain circular corner; the system
    /// shape sits just above that, easing out of the straight edge.
    static let cornerSmoothing: CGFloat = 0.15
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appending(path: "Sources/Speakify/Resources", directoryHint: .isDirectory)
let iconset = resources.appending(path: "AppIcon.iconset", directoryHint: .isDirectory)

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func s(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    value * scale
}

func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}

/// sRGB rather than the calibrated space: calibrated components shift by a
/// noticeable amount on the way to the bitmap (green especially), so the values
/// written here would not be the values that ship.
func rgb(_ red: Int, _ green: Int, _ blue: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

// MARK: - Squircle

/// Corner control points for a continuous-curvature rounded rectangle: two
/// cubics easing out of each straight edge, joined by a circular arc.
private struct SquircleCorner {
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    /// How far the corner reaches along each edge before the edge goes straight.
    let extent: CGFloat
    let arcRadius: CGFloat
    let arcSweep: CGFloat

    init(extent requestedExtent: CGFloat, smoothing: CGFloat, budget: CGFloat) {
        let extent = min(requestedExtent, budget)
        let arcRadius = extent / (1 + smoothing)
        let arcSweep = 90 * (1 - smoothing)
        let arcChord = sin(radians(arcSweep / 2)) * arcRadius * 2.squareRoot()
        let easeAngle = (90 - arcSweep) / 2
        let easeLength = arcRadius * tan(radians(easeAngle / 2))
        let tiltAngle = 45 * smoothing

        self.extent = extent
        self.arcRadius = arcRadius
        self.arcSweep = arcSweep
        c = easeLength * cos(radians(tiltAngle))
        d = c * tan(radians(tiltAngle))
        b = (extent - arcChord - c - d) / 3
        a = 2 * b
    }
}

private func cubicPoint(
    _ p0: CGPoint,
    _ p1: CGPoint,
    _ p2: CGPoint,
    _ p3: CGPoint,
    _ t: CGFloat
) -> CGPoint {
    let mt = 1 - t
    let w0 = mt * mt * mt
    let w1 = 3 * mt * mt * t
    let w2 = 3 * mt * t * t
    let w3 = t * t * t
    return CGPoint(
        x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
        y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y
    )
}

/// One corner sampled in local space, running from the horizontal edge at
/// (-extent, 0) to the vertical edge at (0, -extent), with the corner tip at
/// the origin. The four corners of the shape are mirrored copies of this.
private func squircleCornerPoints(_ corner: SquircleCorner, samples: Int = 28) -> [CGPoint] {
    let extent = corner.extent
    let entry = CGPoint(x: -extent, y: 0)
    let entryControl1 = CGPoint(x: -extent + corner.a, y: 0)
    let entryControl2 = CGPoint(x: -extent + corner.a + corner.b, y: 0)
    let arcStart = CGPoint(x: -extent + corner.a + corner.b + corner.c, y: -corner.d)
    let arcEnd = CGPoint(x: -corner.d, y: -(extent - corner.a - corner.b - corner.c))
    let exitControl1 = CGPoint(x: 0, y: -(extent - corner.a - corner.b))
    let exitControl2 = CGPoint(x: 0, y: -(extent - corner.a))
    let exit = CGPoint(x: 0, y: -extent)

    // By symmetry the arc's centre sits on the corner diagonal at (-m, -m).
    let sum = arcStart.x + arcStart.y
    let squares = arcStart.x * arcStart.x + arcStart.y * arcStart.y
    let discriminant = max(0, sum * sum - 2 * (squares - corner.arcRadius * corner.arcRadius))
    let roots = [(-sum + discriminant.squareRoot()) / 2, (-sum - discriminant.squareRoot()) / 2]
    let m = roots.min(by: { abs($0 - corner.arcRadius) < abs($1 - corner.arcRadius) }) ?? corner.arcRadius
    let centre = CGPoint(x: -m, y: -m)

    var points: [CGPoint] = []
    for step in 0...samples {
        let t = CGFloat(step) / CGFloat(samples)
        points.append(cubicPoint(entry, entryControl1, entryControl2, arcStart, t))
    }

    let startAngle = atan2(arcStart.y - centre.y, arcStart.x - centre.x)
    let endAngle = atan2(arcEnd.y - centre.y, arcEnd.x - centre.x)
    var sweep = endAngle - startAngle
    while sweep > .pi { sweep -= 2 * .pi }
    while sweep < -.pi { sweep += 2 * .pi }
    for step in 1...samples {
        let angle = startAngle + sweep * CGFloat(step) / CGFloat(samples)
        points.append(CGPoint(
            x: centre.x + cos(angle) * corner.arcRadius,
            y: centre.y + sin(angle) * corner.arcRadius
        ))
    }

    for step in 1...samples {
        let t = CGFloat(step) / CGFloat(samples)
        points.append(cubicPoint(arcEnd, exitControl1, exitControl2, exit, t))
    }

    return points
}

/// The macOS 26 app-icon shape: a rounded rectangle whose corners flow out of
/// the straight edges instead of meeting them at a hard tangent.
private func squirclePath(in rect: NSRect, cornerExtent: CGFloat, smoothing: CGFloat) -> NSBezierPath {
    let corner = SquircleCorner(
        extent: cornerExtent,
        smoothing: smoothing,
        budget: min(rect.width, rect.height) / 2
    )
    let local = squircleCornerPoints(corner)
    let path = NSBezierPath()

    func append(_ points: [CGPoint], transform: (CGPoint) -> CGPoint) {
        for point in points {
            let mapped = transform(point)
            if path.isEmpty {
                path.move(to: mapped)
            } else {
                path.line(to: mapped)
            }
        }
    }

    // Clockwise from the top edge: top-right, bottom-right, bottom-left, top-left.
    append(local) { CGPoint(x: rect.maxX + $0.x, y: rect.maxY + $0.y) }
    append(local.reversed()) { CGPoint(x: rect.maxX + $0.x, y: rect.minY - $0.y) }
    append(local) { CGPoint(x: rect.minX - $0.x, y: rect.minY - $0.y) }
    append(local.reversed()) { CGPoint(x: rect.minX - $0.x, y: rect.maxY + $0.y) }
    path.close()

    return path
}

// MARK: - Drawing helpers

func fillPath(_ path: NSBezierPath, with gradient: NSGradient, in rect: NSRect, angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    gradient.draw(in: rect, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
}

/// A soft pool of light. `NSGradient` sizes a radial fill to the *diagonal* of
/// the path's bounds, so the colour has to reach full transparency well before
/// the last stop — otherwise the circle's own edge shows up as a seam.
func drawRadialGlow(centre: CGPoint, radius: CGFloat, color: NSColor) {
    let gradient = NSGradient(colorsAndLocations:
        (color, 0.0),
        (color.withAlphaComponent(color.alphaComponent * 0.55), 0.28),
        (color.withAlphaComponent(color.alphaComponent * 0.16), 0.5),
        (color.withAlphaComponent(0), 0.68)
    )!
    let rect = NSRect(
        x: centre.x - radius,
        y: centre.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
}

/// The waveform, expressed on the 1024 grid. Small icons get fewer, chunkier
/// bars so the silhouette survives once each gap is barely a pixel wide.
private struct GlyphRecipe {
    let barWidth: CGFloat
    let spacing: CGFloat
    let heights: [CGFloat]

    static let full = GlyphRecipe(
        barWidth: 86,
        spacing: 126,
        heights: [206, 376, 562, 376, 206]
    )

    static let simplified = GlyphRecipe(
        barWidth: 122,
        spacing: 202,
        heights: [316, 536, 316]
    )

    static func forIcon(pixels: Int) -> GlyphRecipe {
        pixels <= 32 ? simplified : full
    }
}

func addRoundedVerticalBar(
    in path: NSBezierPath,
    centerX: CGFloat,
    centerY: CGFloat,
    width: CGFloat,
    height: CGFloat
) {
    let rect = NSRect(
        x: centerX - width / 2,
        y: centerY - height / 2,
        width: width,
        height: height
    )
    path.append(NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2))
}

func drawIcon(pixels: Int, to url: URL) throws {
    let size = NSSize(width: pixels, height: pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    bitmap.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext.current?.cgContext else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.current?.imageInterpolation = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let bounds = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    bounds.fill()

    let scale = CGFloat(pixels) / IconMetrics.canvas
    let inset = s(IconMetrics.shapeInset, scale)
    let shapeRect = bounds.insetBy(dx: inset, dy: inset)
    let cornerExtent = s(IconMetrics.cornerExtent, scale)
    let shape = squirclePath(
        in: shapeRect,
        cornerExtent: cornerExtent,
        smoothing: IconMetrics.cornerSmoothing
    )

    // Ambient shadow: barely there, and slightly heavier below, matching the
    // faint alpha ramp the system icons carry outside their shape.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(14, scale)),
        blur: s(38, scale),
        color: NSColor.black.withAlphaComponent(0.16).cgColor
    )
    NSColor.black.setFill()
    shape.fill()
    context.restoreGState()

    // Base gradient: luminous at the top, deepening toward the bottom.
    // A narrow ramp: the corners stay clearly related rather than reading as two
    // different colours, so the surface looks lit instead of tinted.
    let baseGradient = NSGradient(colors: [
        rgb(26, 126, 231),
        rgb(36, 140, 238),
        rgb(50, 156, 244),
        rgb(66, 174, 249)
    ])!
    fillPath(shape, with: baseGradient, in: shapeRect, angle: 86)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Diffuse light spilling in from the upper left.
    drawRadialGlow(
        centre: CGPoint(
            x: shapeRect.minX + shapeRect.width * 0.26,
            y: shapeRect.maxY - shapeRect.height * 0.1
        ),
        radius: shapeRect.width * 1.15,
        color: NSColor.white.withAlphaComponent(0.16)
    )

    // A cooler pool in the lower right keeps the surface from reading flat.
    drawRadialGlow(
        centre: CGPoint(
            x: shapeRect.maxX - shapeRect.width * 0.08,
            y: shapeRect.minY + shapeRect.height * 0.02
        ),
        radius: shapeRect.width * 1.05,
        color: rgb(20, 92, 200, 0.11)
    )

    NSGraphicsContext.restoreGraphicsState()

    // Specular rim: a bright edge along the top that fades away by the bottom,
    // the highlight that reads as glass rather than as a drawn outline.
    let rimWidth = s(5, scale)
    let rimInnerRect = shapeRect.insetBy(dx: rimWidth, dy: rimWidth)
    let rim = squirclePath(
        in: shapeRect,
        cornerExtent: cornerExtent,
        smoothing: IconMetrics.cornerSmoothing
    )
    rim.append(
        squirclePath(
            in: rimInnerRect,
            cornerExtent: cornerExtent - rimWidth,
            smoothing: IconMetrics.cornerSmoothing
        )
    )
    rim.windingRule = .evenOdd
    let rimGradient = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.20), 0.0),
        (NSColor.white.withAlphaComponent(0.05), 0.42),
        (NSColor.white.withAlphaComponent(0.34), 0.86),
        (NSColor.white.withAlphaComponent(0.72), 1.0)
    )!
    fillPath(rim, with: rimGradient, in: shapeRect, angle: 90)

    // Waveform glyph: capsules in a calm arch. Below 32pt the gaps between five
    // bars fall under a pixel and smear into a block, so the small
    // representations carry a simplified three-bar version of the same mark.
    let recipe = GlyphRecipe.forIcon(pixels: pixels)
    let glyph = NSBezierPath()
    let centre = CGPoint(x: bounds.midX, y: bounds.midY)
    let barWidth = s(recipe.barWidth, scale)
    let spacing = s(recipe.spacing, scale)
    let firstOffset = -CGFloat(recipe.heights.count - 1) / 2

    for (index, height) in recipe.heights.enumerated() {
        addRoundedVerticalBar(
            in: glyph,
            centerX: centre.x + (firstOffset + CGFloat(index)) * spacing,
            centerY: centre.y,
            width: barWidth,
            height: s(height, scale)
        )
    }

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(10, scale)),
        blur: s(26, scale),
        color: rgb(6, 40, 122, 0.34).cgColor
    )
    let glyphGradient = NSGradient(colors: [
        rgb(226, 243, 255),
        NSColor.white,
        NSColor.white
    ])!
    fillPath(glyph, with: glyphGradient, in: glyph.bounds, angle: 90)
    context.restoreGState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }

    try pngData.write(to: url)
}

for variant in variants {
    try drawIcon(pixels: variant.pixels, to: iconset.appending(path: variant.name))
}

let process = Process()
process.executableURL = URL(filePath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconset.path(),
    "-o", resources.appending(path: "AppIcon.icns").path()
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw CocoaError(.fileWriteUnknown)
}

try? FileManager.default.removeItem(at: iconset)

print("Generated \(resources.appending(path: "AppIcon.icns").path())")
