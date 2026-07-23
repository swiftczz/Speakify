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

    // Opaque macOS-style rounded-square base with a bright sky-to-cyan gradient.
    let bgRect = NSRect(x: s(58, scale), y: s(58, scale), width: s(908, scale), height: s(908, scale))
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s(214, scale), yRadius: s(214, scale))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s(18, scale)),
        blur: s(32, scale),
        color: NSColor.black.withAlphaComponent(0.12).cgColor
    )
    NSGraphicsContext.saveGraphicsState()
    bgPath.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.96, alpha: 1),   // vivid blue
        NSColor(calibratedRed: 0.18, green: 0.66, blue: 0.99, alpha: 1),   // sky blue
        NSColor(calibratedRed: 0.36, green: 0.87, blue: 0.98, alpha: 1)    // light cyan
    ])?.draw(in: bgRect, angle: 68)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()

    // Airy top-corner glow to keep the surface feeling light.
    let glowRect = NSRect(
        x: bgRect.minX - s(120, scale),
        y: bgRect.maxY - s(430, scale),
        width: s(760, scale),
        height: s(560, scale)
    )
    context.saveGState()
    bgPath.addClip()
    NSGraphicsContext.saveGraphicsState()
    NSGradient(
        starting: NSColor.white.withAlphaComponent(0.32),
        ending: NSColor.white.withAlphaComponent(0)
    )?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)
    NSGraphicsContext.restoreGraphicsState()
    context.restoreGState()

    // Soft inner highlight along the edge.
    let innerHighlightRect = bgRect.insetBy(dx: s(8, scale), dy: s(8, scale))
    let innerHighlight = NSBezierPath(
        roundedRect: innerHighlightRect,
        xRadius: s(206, scale),
        yRadius: s(206, scale)
    )
    NSColor.white.withAlphaComponent(0.45).setStroke()
    innerHighlight.lineWidth = max(0.75, s(2, scale))
    innerHighlight.stroke()

    // Translucent halo behind the waveform for gentle focus.
    let haloMargin = s(176, scale)
    let haloRect = NSRect(
        x: haloMargin,
        y: haloMargin,
        width: CGFloat(pixels) - haloMargin * 2,
        height: CGFloat(pixels) - haloMargin * 2
    )
    NSColor.white.withAlphaComponent(0.14).setFill()
    NSBezierPath(ovalIn: haloRect).fill()
    NSColor.white.withAlphaComponent(0.20).setStroke()
    let haloRing = NSBezierPath(ovalIn: haloRect.insetBy(dx: s(-14, scale), dy: s(-14, scale)))
    haloRing.lineWidth = max(1, s(6, scale))
    haloRing.stroke()

    // Bouncy waveform: a lively rise-and-fall rhythm in crisp white.
    let waveformPath = NSBezierPath()
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let barWidth = s(58, scale)
    let spacing = s(96, scale)
    let heights: [CGFloat] = [150, 300, 470, 560, 380, 220, 130].map { s(CGFloat($0), scale) }
    let centerOffsets: [CGFloat] = [-3, -2, -1, 0, 1, 2, 3].map { CGFloat($0) * spacing }

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
        offset: CGSize(width: 0, height: -s(6, scale)),
        blur: s(14, scale),
        color: NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.55, alpha: 0.28).cgColor
    )
    fillPathWithVerticalGradient(
        waveformPath,
        topColor: NSColor.white,
        bottomColor: NSColor(calibratedRed: 0.88, green: 0.97, blue: 1.0, alpha: 1),
        in: bounds
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
