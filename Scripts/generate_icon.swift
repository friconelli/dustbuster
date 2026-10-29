import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon.iconset"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

// A broom leaning to the right: handle on top, bristles sweeping the bottom-left.
func drawBroom(size: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    context.translateBy(x: size * 0.53, y: size * 0.53)
    context.rotate(by: -0.6)

    let u = size / 100
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -u * 1.5)
    shadow.shadowBlurRadius = u * 3
    shadow.set()

    // Handle
    NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.62, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: NSRect(x: -3.5 * u, y: 2 * u, width: 7 * u, height: 42 * u),
                 xRadius: 3.5 * u, yRadius: 3.5 * u).fill()

    // Bristles: a fan widening downwards
    let bristles = NSBezierPath()
    bristles.move(to: NSPoint(x: -10 * u, y: 0))
    bristles.line(to: NSPoint(x: 10 * u, y: 0))
    bristles.curve(to: NSPoint(x: 21 * u, y: -34 * u),
                   controlPoint1: NSPoint(x: 15 * u, y: -10 * u),
                   controlPoint2: NSPoint(x: 20 * u, y: -24 * u))
    bristles.line(to: NSPoint(x: -21 * u, y: -34 * u))
    bristles.curve(to: NSPoint(x: -10 * u, y: 0),
                   controlPoint1: NSPoint(x: -20 * u, y: -24 * u),
                   controlPoint2: NSPoint(x: -15 * u, y: -10 * u))
    bristles.close()
    NSColor.white.setFill()
    bristles.fill()
    NSShadow().set()

    // Bristle grooves
    NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.55, alpha: 0.35).setStroke()
    for i in -2...2 {
        let x = CGFloat(i)
        let groove = NSBezierPath()
        groove.move(to: NSPoint(x: x * 3 * u, y: -9 * u))
        groove.line(to: NSPoint(x: x * 7 * u, y: -32 * u))
        groove.lineWidth = 1.6 * u
        groove.lineCapStyle = .round
        groove.stroke()
    }

    // Binding band
    NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.30, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: NSRect(x: -12 * u, y: -6 * u, width: 24 * u, height: 8 * u),
                 xRadius: 2.5 * u, yRadius: 2.5 * u).fill()

    context.restoreGState()
}

// Four-pointed sparkle star.
func drawSparkle(center: NSPoint, radius: CGFloat) {
    let inner = radius * 0.28
    let path = NSBezierPath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 2
        let r = i % 2 == 0 ? radius : inner
        let point = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    NSColor.white.setFill()
    path.fill()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let radius = size * 0.22
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.10, green: 0.75, blue: 0.55, alpha: 1.0),
            NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.55, alpha: 1.0),
        ])
        gradient?.draw(in: path, angle: -60)

        drawBroom(size: size)
        drawSparkle(center: NSPoint(x: size * 0.25, y: size * 0.73), radius: size * 0.085)
        drawSparkle(center: NSPoint(x: size * 0.15, y: size * 0.52), radius: size * 0.045)
        drawSparkle(center: NSPoint(x: size * 0.38, y: size * 0.86), radius: size * 0.04)

        return true
    }
    return image
}

for entry in sizes {
    let size = CGFloat(entry.px)
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to render \(entry.name)")
        continue
    }
    let path = "\(outputDir)/\(entry.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}
