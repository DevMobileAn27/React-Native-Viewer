import AppKit
import Foundation

struct IconSpec {
    let idiom: String
    let size: Int
    let scale: Int
    let filename: String

    var pixelSize: Int { size * scale }

    var contentsEntry: [String: String] {
        [
            "idiom": idiom,
            "size": "\(size)x\(size)",
            "scale": "\(scale)x",
            "filename": filename,
        ]
    }
}

struct Palette {
    let backgroundStart = NSColor(srgbRed: 0.05, green: 0.10, blue: 0.18, alpha: 1)
    let backgroundMid = NSColor(srgbRed: 0.07, green: 0.26, blue: 0.43, alpha: 1)
    let backgroundEnd = NSColor(srgbRed: 0.10, green: 0.64, blue: 0.84, alpha: 1)
    let panelFill = NSColor(srgbRed: 0.03, green: 0.06, blue: 0.11, alpha: 0.68)
    let panelStroke = NSColor.white.withAlphaComponent(0.20)
    let panelHeader = NSColor.white.withAlphaComponent(0.12)
    let orbitStroke = NSColor(srgbRed: 0.52, green: 0.90, blue: 1.0, alpha: 0.30)
    let highlight = NSColor.white.withAlphaComponent(0.24)
    let title = NSColor(calibratedWhite: 0.98, alpha: 1)
    let cursor = NSColor(srgbRed: 0.41, green: 0.94, blue: 0.86, alpha: 1)
    let dot = NSColor(srgbRed: 0.63, green: 0.89, blue: 1.0, alpha: 0.95)
    let shadow = NSColor.black.withAlphaComponent(0.18)
}

let specs = [
    IconSpec(idiom: "mac", size: 16, scale: 1, filename: "icon_16x16.png"),
    IconSpec(idiom: "mac", size: 16, scale: 2, filename: "icon_16x16@2x.png"),
    IconSpec(idiom: "mac", size: 32, scale: 1, filename: "icon_32x32.png"),
    IconSpec(idiom: "mac", size: 32, scale: 2, filename: "icon_32x32@2x.png"),
    IconSpec(idiom: "mac", size: 128, scale: 1, filename: "icon_128x128.png"),
    IconSpec(idiom: "mac", size: 128, scale: 2, filename: "icon_128x128@2x.png"),
    IconSpec(idiom: "mac", size: 256, scale: 1, filename: "icon_256x256.png"),
    IconSpec(idiom: "mac", size: 256, scale: 2, filename: "icon_256x256@2x.png"),
    IconSpec(idiom: "mac", size: 512, scale: 1, filename: "icon_512x512.png"),
    IconSpec(idiom: "mac", size: 512, scale: 2, filename: "icon_512x512@2x.png"),
]

let outputPath: String
if let providedPath = CommandLine.arguments.dropFirst().first {
    outputPath = providedPath
} else {
    outputPath = "React Native Viewer/Assets.xcassets/AppIcon.appiconset"
}

let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

if let existingFiles = try? fileManager.contentsOfDirectory(at: outputURL, includingPropertiesForKeys: nil) {
    for fileURL in existingFiles where fileURL.pathExtension.lowercased() == "png" {
        try? fileManager.removeItem(at: fileURL)
    }
}

let palette = Palette()
for spec in specs {
    autoreleasepool {
        let data = renderIcon(pixelSize: spec.pixelSize, palette: palette)
        let destinationURL = outputURL.appendingPathComponent(spec.filename)
        try? data.write(to: destinationURL)
        print("Generated \(spec.filename)")
    }
}

let jsonObject: [String: Any] = [
    "images": specs.map(\.contentsEntry),
    "info": [
        "author": "codex",
        "version": 1,
    ],
]

let jsonData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys])
try jsonData.write(to: outputURL.appendingPathComponent("Contents.json"))
print("Updated Contents.json")

func renderIcon(pixelSize: Int, palette: Palette) -> Data {
    let size = CGFloat(pixelSize)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    context.imageInterpolation = .high

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    let canvas = CGRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let iconRect = canvas.insetBy(dx: size * 0.035, dy: size * 0.035)
    let radius = size * 0.23
    let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    let backgroundGradient = NSGradient(
        colorsAndLocations:
            (palette.backgroundStart, 0.0),
            (palette.backgroundMid, 0.55),
            (palette.backgroundEnd, 1.0)
    )!
    backgroundGradient.draw(in: iconPath, angle: -32)

    drawHighlight(in: iconRect, palette: palette)
    drawOrbits(in: iconRect, palette: palette)
    drawConsole(in: iconRect, pixelSize: pixelSize, palette: palette)

    palette.highlight.setStroke()
    iconPath.lineWidth = max(2, size * 0.010)
    iconPath.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func drawHighlight(in rect: CGRect, palette: Palette) {
    let glowRect = CGRect(
        x: rect.minX + rect.width * 0.06,
        y: rect.midY,
        width: rect.width * 0.88,
        height: rect.height * 0.52
    )
    let glowPath = NSBezierPath(ovalIn: glowRect)
    let glowGradient = NSGradient(
        colorsAndLocations:
            (palette.highlight, 0.0),
            (palette.highlight.withAlphaComponent(0.08), 0.35),
            (NSColor.clear, 1.0)
    )!
    glowGradient.draw(in: glowPath, relativeCenterPosition: NSPoint(x: -0.35, y: 0.68))
}

func drawOrbits(in rect: CGRect, palette: Palette) {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let orbitSize = CGSize(width: rect.width * 0.58, height: rect.height * 0.22)

    for angle in [0.0, 60.0, -60.0] {
        let orbitRect = CGRect(
            x: center.x - orbitSize.width / 2,
            y: center.y - orbitSize.height / 2,
            width: orbitSize.width,
            height: orbitSize.height
        )
        let path = NSBezierPath(ovalIn: orbitRect)
        var transform = AffineTransform()
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: angle)
        transform.translate(x: -center.x, y: -center.y)
        path.transform(using: transform)
        path.lineWidth = rect.width * 0.020
        palette.orbitStroke.setStroke()
        path.stroke()
    }
}

func drawConsole(in rect: CGRect, pixelSize: Int, palette: Palette) {
    let panelRect = CGRect(
        x: rect.minX + rect.width * 0.18,
        y: rect.minY + rect.height * 0.22,
        width: rect.width * 0.64,
        height: rect.height * 0.46
    )
    let panelRadius = rect.width * 0.08
    let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: panelRadius, yRadius: panelRadius)

    let shadow = NSShadow()
    shadow.shadowColor = palette.shadow
    shadow.shadowBlurRadius = rect.width * 0.04
    shadow.shadowOffset = CGSize(width: 0, height: -rect.width * 0.02)
    shadow.set()

    palette.panelFill.setFill()
    panelPath.fill()

    NSGraphicsContext.current?.saveGraphicsState()
    panelPath.addClip()

    let headerRect = CGRect(
        x: panelRect.minX,
        y: panelRect.maxY - panelRect.height * 0.22,
        width: panelRect.width,
        height: panelRect.height * 0.22
    )
    palette.panelHeader.setFill()
    headerRect.fill()

    if pixelSize >= 64 {
        let dotSize = rect.width * 0.030
        let dotSpacing = dotSize * 1.55
        for index in 0..<3 {
            let dotRect = CGRect(
                x: panelRect.minX + rect.width * 0.06 + CGFloat(index) * dotSpacing,
                y: headerRect.midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            let dotPath = NSBezierPath(ovalIn: dotRect)
            palette.dot.setFill()
            dotPath.fill()
        }
    }

    NSGraphicsContext.current?.restoreGraphicsState()

    palette.panelStroke.setStroke()
    panelPath.lineWidth = max(1.5, rect.width * 0.010)
    panelPath.stroke()

    let title = NSAttributedString(
        string: "RN",
        attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: rect.width * 0.24, weight: .black),
            .foregroundColor: palette.title,
            .kern: -rect.width * 0.012,
        ]
    )
    let titleSize = title.size()
    let titleRect = CGRect(
        x: panelRect.midX - titleSize.width / 2,
        y: panelRect.midY - titleSize.height / 2 - rect.height * 0.03,
        width: titleSize.width,
        height: titleSize.height
    )
    title.draw(in: titleRect)

    let cursorRect = CGRect(
        x: panelRect.midX + titleSize.width * 0.18,
        y: panelRect.minY + panelRect.height * 0.18,
        width: rect.width * 0.11,
        height: rect.width * 0.032
    )
    let cursorPath = NSBezierPath(roundedRect: cursorRect, xRadius: cursorRect.height / 2, yRadius: cursorRect.height / 2)
    palette.cursor.setFill()
    cursorPath.fill()
}
