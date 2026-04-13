import AppKit
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
defer { image.unlockFocus() }

let rect = CGRect(origin: .zero, size: size)
let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: 228, yRadius: 228)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.18, alpha: 1),
])!
gradient.draw(in: backgroundPath, angle: -90)

NSGraphicsContext.current?.saveGraphicsState()
backgroundPath.addClip()

let glowPath = NSBezierPath(ovalIn: CGRect(x: -90, y: 610, width: 760, height: 500))
NSColor(calibratedRed: 0.24, green: 0.58, blue: 1.0, alpha: 0.28).setFill()
glowPath.fill()

let accentPath = NSBezierPath()
accentPath.move(to: CGPoint(x: 650, y: 170))
accentPath.line(to: CGPoint(x: 965, y: 520))
accentPath.line(to: CGPoint(x: 965, y: 1024))
accentPath.line(to: CGPoint(x: 390, y: 1024))
accentPath.close()
NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.95, alpha: 0.18).setFill()
accentPath.fill()

let slashShadow = NSBezierPath()
slashShadow.move(to: CGPoint(x: 566, y: 216))
slashShadow.line(to: CGPoint(x: 744, y: 216))
slashShadow.line(to: CGPoint(x: 502, y: 808))
slashShadow.line(to: CGPoint(x: 324, y: 808))
slashShadow.close()
NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
slashShadow.fill()

let slashPath = NSBezierPath()
slashPath.move(to: CGPoint(x: 548, y: 240))
slashPath.line(to: CGPoint(x: 708, y: 240))
slashPath.line(to: CGPoint(x: 466, y: 784))
slashPath.line(to: CGPoint(x: 306, y: 784))
slashPath.close()
NSColor(calibratedRed: 0.28, green: 0.65, blue: 1.0, alpha: 1).setFill()
slashPath.fill()

NSGraphicsContext.current?.restoreGraphicsState()

let letterShadow = NSShadow()
letterShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.18)
letterShadow.shadowOffset = NSSize(width: 0, height: -18)
letterShadow.shadowBlurRadius = 24

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center

let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 540, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .shadow: letterShadow,
]

let letter = NSAttributedString(string: "D", attributes: attributes)
let textRect = CGRect(x: 145, y: 200, width: 540, height: 620)
letter.draw(in: textRect)

func savePNG(named name: String, size: Int) throws {
    let targetSize = CGSize(width: size, height: size)
    let resized = NSImage(size: targetSize)
    resized.lockFocus()
    image.draw(
        in: CGRect(origin: .zero, size: targetSize),
        from: rect,
        operation: .copy,
        fraction: 1
    )
    resized.unlockFocus()

    guard
        let tiffData = resized.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DashTypeIcon", code: 1)
    }

    try pngData.write(to: outputURL.appendingPathComponent(name))
}

let filenames: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixelSize) in filenames {
    try savePNG(named: name, size: pixelSize)
}
