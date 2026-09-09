#!/usr/bin/env swift
import AppKit
import CoreText
import Foundation

/// Full-bleed 1024 artwork (Dock applies the squircle) plus a menu-bar template PDF.
/// A: platinum glass, viewfinder corners, Latin A + 文.

enum GlyphSet {
    case corners
    case wen
    case pair
}

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outDir = root.appendingPathComponent("App/Icons")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let masterSize: CGFloat = 1024
let menuSize: CGFloat = 18

func wenFont(size: CGFloat) -> NSFont {
    let names = [
        "PingFangSC-Medium",
        "PingFangSC-Regular",
        "HiraginoSansGB-W3",
        "Hiragino Sans GB",
    ]
    for name in names {
        if let font = NSFont(name: name, size: size) { return font }
    }
    return NSFont.systemFont(ofSize: size, weight: .medium)
}

func drawViewfinder(
    in rect: CGRect,
    length: CGFloat,
    lineWidth: CGFloat,
    color: NSColor
) {
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    let x0 = rect.minX
    let y0 = rect.minY
    let x1 = rect.maxX
    let y1 = rect.maxY

    path.move(to: NSPoint(x: x0, y: y0 + length))
    path.line(to: NSPoint(x: x0, y: y0))
    path.line(to: NSPoint(x: x0 + length, y: y0))

    path.move(to: NSPoint(x: x1 - length, y: y0))
    path.line(to: NSPoint(x: x1, y: y0))
    path.line(to: NSPoint(x: x1, y: y0 + length))

    path.move(to: NSPoint(x: x1, y: y1 - length))
    path.line(to: NSPoint(x: x1, y: y1))
    path.line(to: NSPoint(x: x1 - length, y: y1))

    path.move(to: NSPoint(x: x0 + length, y: y1))
    path.line(to: NSPoint(x: x0, y: y1))
    path.line(to: NSPoint(x: x0, y: y1 - length))

    color.setStroke()
    path.stroke()
}

func fillRadialGlass(size: CGFloat) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let colors = [
        NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.92, alpha: 1),
        NSColor(calibratedRed: 0.58, green: 0.65, blue: 0.74, alpha: 1),
    ]
    var locations: [CGFloat] = [0, 1]
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors.map(\.cgColor) as CFArray,
        locations: &locations
    ) else { return }

    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: size * 0.36, y: size * 0.74),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.52, y: size * 0.42),
        endRadius: size * 0.95,
        options: [.drawsAfterEndLocation]
    )

    var shineLoc: [CGFloat] = [0, 1]
    let shineColors = [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0),
    ]
    if let shine = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: shineColors.map(\.cgColor) as CFArray,
        locations: &shineLoc
    ) {
        ctx.drawLinearGradient(
            shine,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: 0, y: size * 0.52),
            options: []
        )
    }
}

func makeLine(_ string: String, font: NSFont, color: NSColor) -> CTLine {
    let attr = NSAttributedString(
        string: string,
        attributes: [
            .font: font,
            .foregroundColor: color,
        ]
    )
    return CTLineCreateWithAttributedString(attr)
}

func inkBounds(_ line: CTLine, in ctx: CGContext) -> CGRect {
    ctx.textPosition = .zero
    return CTLineGetImageBounds(line, ctx)
}

/// Bitmap contexts already flip Y; Core Text would draw A/文 upside down unless we undo it.
var flipTextVertically = false

func drawLine(_ line: CTLine, origin: CGPoint, in ctx: CGContext) {
    ctx.saveGState()
    ctx.textMatrix = .identity
    let ink = inkBounds(line, in: ctx)
    let center = CGPoint(x: origin.x + ink.midX, y: origin.y + ink.midY)
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: flipTextVertically ? -1 : 1)
    ctx.textPosition = CGPoint(x: -ink.midX, y: -ink.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func drawGlyphs(in canvas: CGRect, size: CGFloat, set: GlyphSet, color: NSColor) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.saveGState()
    ctx.setFillColor(color.cgColor)

    let aLine = makeLine("A", font: NSFont.systemFont(ofSize: size * 0.255, weight: .medium), color: color)
    let wLine = makeLine("文", font: wenFont(size: size * 0.236), color: color)
    let aInk = inkBounds(aLine, in: ctx)
    let wInk = inkBounds(wLine, in: ctx)

    switch set {
    case .corners:
        break
    case .wen:
        let wen = makeLine("文", font: wenFont(size: size * 0.42), color: color)
        let ink = inkBounds(wen, in: ctx)
        drawLine(
            wen,
            origin: CGPoint(x: canvas.midX - ink.midX, y: canvas.midY - ink.midY),
            in: ctx
        )
    case .pair:
        let overlap = size * 0.03
        let total = aInk.width + wInk.width - overlap
        let startX = canvas.midX - total / 2
        drawLine(
            aLine,
            origin: CGPoint(
                x: startX - aInk.minX,
                y: canvas.midY - aInk.midY + size * 0.006
            ),
            in: ctx
        )
        drawLine(
            wLine,
            origin: CGPoint(
                x: startX + aInk.width - overlap - wInk.minX,
                y: canvas.midY - wInk.midY + size * 0.002
            ),
            in: ctx
        )
    }
    ctx.restoreGState()
}

func glyphSet(forPixelSize px: CGFloat) -> GlyphSet {
    if px <= 16 { return .corners }
    if px <= 32 { return .wen }
    return .pair
}

func drawAppIcon(size: CGFloat, glyphs: GlyphSet? = nil) {
    fillRadialGlass(size: size)

    let inset = size * 0.198
    let frame = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let line = max(size * 0.0235, 1.25)
    let length = size * 0.118
    let set = glyphs ?? glyphSet(forPixelSize: size)
    let mark = NSColor.white.withAlphaComponent(0.97)

    if size >= 64 {
        NSGraphicsContext.current?.cgContext.setShadow(
            offset: CGSize(width: 0, height: -size * 0.004),
            blur: size * 0.01,
            color: NSColor.black.withAlphaComponent(0.14).cgColor
        )
    }
    drawViewfinder(in: frame, length: length, lineWidth: line, color: mark)
    drawGlyphs(in: frame, size: size, set: set, color: mark)
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
}

func drawMenuBarIcon(in canvas: CGRect) {
    let w = canvas.width
    let line = max(w * 0.09, 1.15)
    let inset = w * 0.125
    let frame = canvas.insetBy(dx: inset, dy: inset)
    drawViewfinder(
        in: frame,
        length: w * 0.23,
        lineWidth: line,
        color: .black
    )

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let wen = makeLine("文", font: wenFont(size: w * 0.42), color: .black)
    let ink = inkBounds(wen, in: ctx)
    drawLine(
        wen,
        origin: CGPoint(x: canvas.midX - ink.midX, y: canvas.midY - ink.midY),
        in: ctx
    )
}

func renderPNG(size: CGFloat, url: URL, draw: () -> Void) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "generate-icons", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        flipTextVertically = true
    }
    draw()
    flipTextVertically = false
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate-icons", code: 1)
    }
    try png.write(to: url)
}

func renderPDF(size: CGFloat, url: URL, draw: () -> Void) {
    var mediaBox = CGRect(x: 0, y: 0, width: size, height: size)
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fputs("error: could not create PDF \(url.path)\n", stderr)
        exit(1)
    }
    ctx.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()
}

func squirclePath(in rect: CGRect) -> NSBezierPath {
    let radius = min(rect.width, rect.height) * 0.223
    return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawDockPreview(size: CGFloat) {
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: size, height: size)).fill()

    let pad = size * 0.14
    let iconRect = CGRect(x: pad, y: pad, width: size - pad * 2, height: size - pad * 2)
    let path = squirclePath(in: iconRect)

    NSGraphicsContext.current?.cgContext.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.04,
        color: NSColor.black.withAlphaComponent(0.22).cgColor
    )
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    path.addClip()
    NSGraphicsContext.current?.cgContext.translateBy(x: pad, y: pad)
    let scale = (size - pad * 2) / masterSize
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    drawAppIcon(size: masterSize, glyphs: .pair)
}

func setDPI(url: URL, dpi: Int) throws {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    proc.arguments = [
        "-s", "dpiWidth", "\(dpi)",
        "-s", "dpiHeight", "\(dpi)",
        url.path,
    ]
    try proc.run()
    proc.waitUntilExit()
    if proc.terminationStatus != 0 {
        fputs("sips dpi failed for \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
}

let masterURL = outDir.appendingPathComponent("AppIcon.png")
let previewURL = outDir.appendingPathComponent("AppIcon-preview.png")
let menuPDF = outDir.appendingPathComponent("MenuBarIconTemplate.pdf")
let menuPNG = outDir.appendingPathComponent("MenuBarIconTemplate.png")
let menuPNG2x = outDir.appendingPathComponent("MenuBarIconTemplate@2x.png")
let menuPreview = outDir.appendingPathComponent("MenuBarIcon-preview.png")

try renderPNG(size: masterSize, url: masterURL) {
    drawAppIcon(size: masterSize, glyphs: .pair)
}
try renderPNG(size: 1024, url: previewURL) {
    drawDockPreview(size: 1024)
}
try renderPNG(size: 18, url: menuPNG) {
    drawMenuBarIcon(in: CGRect(x: 0, y: 0, width: 18, height: 18))
}
try renderPNG(size: 36, url: menuPNG2x) {
    NSGraphicsContext.current?.cgContext.scaleBy(x: 2, y: 2)
    drawMenuBarIcon(in: CGRect(x: 0, y: 0, width: 18, height: 18))
}
try renderPNG(size: 144, url: menuPreview) {
    NSColor(calibratedWhite: 0.957, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: 144, height: 144)).fill()
    NSGraphicsContext.current?.cgContext.scaleBy(x: 8, y: 8)
    drawMenuBarIcon(in: CGRect(x: 0, y: 0, width: 18, height: 18))
}
renderPDF(size: menuSize, url: menuPDF) {
    drawMenuBarIcon(in: CGRect(x: 0, y: 0, width: menuSize, height: menuSize))
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let variants: [(String, Int, Int)] = [
    ("icon_16x16.png", 16, 72),
    ("icon_16x16@2x.png", 32, 144),
    ("icon_32x32.png", 32, 72),
    ("icon_32x32@2x.png", 64, 144),
    ("icon_128x128.png", 128, 72),
    ("icon_128x128@2x.png", 256, 144),
    ("icon_256x256.png", 256, 72),
    ("icon_256x256@2x.png", 512, 144),
    ("icon_512x512.png", 512, 72),
    ("icon_512x512@2x.png", 1024, 144),
]

for (name, px, dpi) in variants {
    let dest = iconset.appendingPathComponent(name)
    try renderPNG(size: CGFloat(px), url: dest) {
        drawAppIcon(size: CGFloat(px))
    }
    try setDPI(url: dest, dpi: dpi)
}

let icns = outDir.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
if iconutil.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(1)
}
try FileManager.default.removeItem(at: iconset)

print("wrote \(masterURL.path)")
print("wrote \(previewURL.path)")
print("wrote \(icns.path)")
print("wrote \(menuPDF.path)")
