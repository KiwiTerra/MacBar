import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 56, y: 56, width: 912, height: 912), xRadius: 206, yRadius: 206).fill()
        NSColor(calibratedRed: 0.43, green: 0.70, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 192, y: 384, width: 420, height: 374), xRadius: 45, yRadius: 45).fill()
        NSColor(calibratedRed: 0.84, green: 0.91, blue: 0.99, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 446, y: 320, width: 386, height: 304), xRadius: 42, yRadius: 42).fill()
        NSColor(calibratedRed: 0.29, green: 0.34, blue: 0.43, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 170, y: 183, width: 684, height: 76), xRadius: 25, yRadius: 25).fill()
        for x in [CGFloat(355), 468, 581] {
            NSColor(calibratedWhite: x == 468 ? 1 : 0.65, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 202, width: 51, height: 38), xRadius: 8, yRadius: 8).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
