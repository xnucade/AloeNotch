// Generates the AppIcon PNG set: a dark macOS-style rounded square with a
// notch silhouette at the top and the app's signature ambient glow line
// tracing its edge. Run whenever you want to regenerate:
//   swift scripts/generate-icon.swift
// Output: OpenNotch/Assets.xcassets/AppIcon.appiconset/*.png
import AppKit

let outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("OpenNotch/Assets.xcassets/AppIcon.appiconset")

/// Bottom-rounded notch silhouette in CG (bottom-left origin) coordinates.
func notchPath(rect: CGRect, r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r),
             radius: r, startAngle: .pi, endAngle: .pi * 1.5, clockwise: false)
    p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
             radius: r, startAngle: .pi * 1.5, endAngle: 0, clockwise: false)
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    p.closeSubpath()
    return p
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    let s = CGFloat(px) / 1024.0

    // Apple's macOS icon grid: 824pt rounded square centered in 1024.
    let square = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let squarePath = CGPath(
        roundedRect: square, cornerWidth: 186 * s, cornerHeight: 186 * s,
        transform: nil
    )
    ctx.addPath(squarePath)
    ctx.clip()

    // Background: deep navy fading to near-black.
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(
        colorsSpace: space,
        colors: [
            CGColor(red: 0.11, green: 0.12, blue: 0.22, alpha: 1),
            CGColor(red: 0.02, green: 0.02, blue: 0.05, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: square.midX, y: square.maxY),
        end: CGPoint(x: square.midX, y: square.minY),
        options: []
    )

    // Notch flush with the top of the square.
    let notch = CGRect(
        x: square.midX - 210 * s, y: square.maxY - 130 * s,
        width: 420 * s, height: 130 * s
    )
    let path = notchPath(rect: notch, r: 56 * s)

    // Ambient glow line: layered strokes with shadow for the bloom.
    let accent = CGColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60 * s, color: accent)
    ctx.addPath(path)
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(14 * s)
    ctx.strokePath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18 * s, color: accent)
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 1))
    ctx.setLineWidth(7 * s)
    ctx.strokePath()
    ctx.restoreGState()

    // The notch itself, pure black over everything.
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        let file = outputDir.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try render(px: size * scale).write(to: file)
        print("wrote \(file.lastPathComponent)")
    }
}
