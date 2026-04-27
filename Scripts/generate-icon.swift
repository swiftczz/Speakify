#!/usr/bin/env swift

import AppKit
import Foundation

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

func fillPathWithVerticalGradient(
    _ path: NSBezierPath,
    topColor: NSColor,
    bottomColor: NSColor,
    in rect: NSRect,
    angle: CGFloat = 90
) {
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: bottomColor, ending: topColor)?.draw(in: rect, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
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

    let scale = CGFloat(pixels) / 1024.0

    // Opaque macOS-style rounded-square base.
    let bgRect = NSRect(x: s(58, scale), y: s(58, scale), width: s(908, scale), height: s(908, scale))
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s(214, scale), yRadius: s(214, scale))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(18, scale)),
        blur: s(32, scale),
        color: NSColor.black.withAlphaComponent(0.10).cgColor
    )
    fillPathWithVerticalGradient(
        bgPath,
        topColor: NSColor(calibratedWhite: 0.995, alpha: 1),
        bottomColor: NSColor(calibratedWhite: 0.925, alpha: 1),
        in: bgRect
    )
    context.restoreGState()

    // Refined outer edge and inner highlight.
    NSColor(calibratedWhite: 0.80, alpha: 0.72).setStroke()
    bgPath.lineWidth = max(1, s(2.2, scale))
    bgPath.stroke()

    let innerHighlightRect = bgRect.insetBy(dx: s(8, scale), dy: s(8, scale))
    let innerHighlight = NSBezierPath(
        roundedRect: innerHighlightRect,
        xRadius: s(206, scale),
        yRadius: s(206, scale)
    )
    NSColor.white.withAlphaComponent(0.72).setStroke()
    innerHighlight.lineWidth = max(0.75, s(1.5, scale))
    innerHighlight.stroke()

    // Larger deep-charcoal circular core with subtle depth.
    let circleMargin = s(138, scale)
    let circleRect = NSRect(
        x: circleMargin,
        y: circleMargin,
        width: CGFloat(pixels) - circleMargin * 2,
        height: CGFloat(pixels) - circleMargin * 2
    )
    let circlePath = NSBezierPath(ovalIn: circleRect)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(10, scale)),
        blur: s(24, scale),
        color: NSColor.black.withAlphaComponent(0.30).cgColor
    )
    fillPathWithVerticalGradient(
        circlePath,
        topColor: NSColor(calibratedWhite: 0.22, alpha: 1),
        bottomColor: NSColor(calibratedWhite: 0.045, alpha: 1),
        in: circleRect
    )
    context.restoreGState()

    NSColor.black.withAlphaComponent(0.42).setStroke()
    circlePath.lineWidth = max(1, s(2, scale))
    circlePath.stroke()

    // Subtle top sheen on the circular core.
    let sheenRect = NSRect(
        x: circleRect.minX + s(54, scale),
        y: circleRect.midY + s(66, scale),
        width: circleRect.width - s(108, scale),
        height: s(170, scale)
    )
    let sheenPath = NSBezierPath(ovalIn: sheenRect)
    context.saveGState()
    circlePath.addClip()
    NSColor.white.withAlphaComponent(0.045).setFill()
    sheenPath.fill()
    context.restoreGState()

    // Custom waveform instead of SF Symbol, tuned for the optimized logo.
    // The two tallest center bars subtly imply "11" for stronger brand memory.
    let waveformPath = NSBezierPath()
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let barWidth = s(42, scale)
    let spacing = s(76, scale)
    let heights: [CGFloat] = [112, 220, 370, 370, 220, 112].map { s(CGFloat($0), scale) }
    let centerOffsets: [CGFloat] = [-2.5, -1.5, -0.5, 0.5, 1.5, 2.5].map { CGFloat($0) * spacing }

    for (index, offset) in centerOffsets.enumerated() {
        addRoundedVerticalBar(
            in: waveformPath,
            centerX: center.x + offset,
            centerY: center.y,
            width: barWidth,
            height: heights[index]
        )
    }

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(2, scale)),
        blur: s(4, scale),
        color: NSColor.black.withAlphaComponent(0.18).cgColor
    )
    fillPathWithVerticalGradient(
        waveformPath,
        topColor: NSColor.white,
        bottomColor: NSColor(calibratedWhite: 0.92, alpha: 1),
        in: circleRect
    )
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
