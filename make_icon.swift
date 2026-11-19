import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconsetURL = URL(fileURLWithPath: "AppIcon.iconset", isDirectory: true)
let fm = FileManager.default
try? fm.removeItem(at: iconsetURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(name: String, px: Int)] = [
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

func renderIcon(pixelSize: Int, to url: URL) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Failed to create CGContext")
    }

    let scale = CGFloat(pixelSize) / 1024.0
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high

    // Standard macOS app icon squircle (824x824 centered inside 1024x1024)
    let cardRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: cardRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 1. Soft drop shadow beneath the icon
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14),
        blur: 28,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
    )
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip inside the squircle for all interior artwork
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Dynamic Aerial-inspired wallpaper gradient
    let gradColors = [
        CGColor(red: 0.06, green: 0.11, blue: 0.24, alpha: 1), // Deep midnight indigo
        CGColor(red: 0.10, green: 0.30, blue: 0.48, alpha: 1), // Ocean blue
        CGColor(red: 0.22, green: 0.56, blue: 0.64, alpha: 1), // Aerial teal
        CGColor(red: 0.94, green: 0.62, blue: 0.30, alpha: 1)  // Warm horizon glow
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.38, 0.72, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 512, y: 100),
            end: CGPoint(x: 512, y: 780),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }

    // Subtle landscape ridge wave at the bottom
    let ridge = CGMutablePath()
    ridge.move(to: CGPoint(x: 100, y: 100))
    ridge.addLine(to: CGPoint(x: 100, y: 310))
    ridge.addCurve(
        to: CGPoint(x: 560, y: 270),
        control1: CGPoint(x: 260, y: 390),
        control2: CGPoint(x: 410, y: 230)
    )
    ridge.addCurve(
        to: CGPoint(x: 924, y: 340),
        control1: CGPoint(x: 700, y: 310),
        control2: CGPoint(x: 820, y: 385)
    )
    ridge.addLine(to: CGPoint(x: 924, y: 100))
    ridge.closeSubpath()
    ctx.addPath(ridge)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.07, blue: 0.15, alpha: 0.52))
    ctx.fillPath()

    // Frosted video play emblem centered in the wallpaper region
    let playCenter = CGPoint(x: 512, y: 430)
    let circleRect = CGRect(x: playCenter.x - 130, y: playCenter.y - 130, width: 260, height: 260)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.fillEllipse(in: circleRect)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.42))
    ctx.setLineWidth(6)
    ctx.strokeEllipse(in: circleRect)

    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: playCenter.x - 36, y: playCenter.y + 56))
    tri.addLine(to: CGPoint(x: playCenter.x + 62, y: playCenter.y))
    tri.addLine(to: CGPoint(x: playCenter.x - 36, y: playCenter.y - 56))
    tri.closeSubpath()
    ctx.addPath(tri)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.94))
    ctx.fillPath()

    // 3. Solid black menu bar across the top edge (with subtle notch silhouette)
    let barBottom: CGFloat = 758
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 100, y: barBottom, width: 824, height: 924 - barBottom))

    // Subtle notch cutout outline tucked inside the black bar to signify notch-hiding
    let notchRect = CGRect(x: 412, y: barBottom + 20, width: 200, height: 146)
    let notchPath = CGPath(roundedRect: notchRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    ctx.addPath(notchPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // Crisp hairline divider along the bottom edge of the black menu bar
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.fill(CGRect(x: 100, y: barBottom - 2, width: 824, height: 3))

    // Minimalist white menu bar status dots (left & right of notch)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.fillEllipse(in: CGRect(x: 196, y: 824, width: 24, height: 24))
    let leftPill = CGPath(roundedRect: CGRect(x: 242, y: 829, width: 92, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(leftPill)
    ctx.fillPath()

    let rightPill1 = CGPath(roundedRect: CGRect(x: 686, y: 829, width: 64, height: 14), cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(rightPill1)
    ctx.fillPath()
    let rightPill2 = CGPath(roundedRect: CGRect(x: 770, y: 824, width: 52, height: 24), cornerWidth: 7, cornerHeight: 7, transform: nil)
    ctx.addPath(rightPill2)
    ctx.fillPath()

    ctx.restoreGState()

    // 4. Subtle inner highlight border around the entire squircle
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(4)
    ctx.strokePath()

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              url as CFURL,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        fatalError("Failed to write PNG to \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for spec in specs {
    try renderIcon(pixelSize: spec.px, to: iconsetURL.appendingPathComponent(spec.name))
}
print("Generated AppIcon.iconset")