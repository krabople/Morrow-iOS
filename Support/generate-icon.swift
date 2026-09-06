import AppKit

let output = CommandLine.arguments.dropFirst().first
    ?? "Morrow/Resources/Assets.xcassets/AppIcon.appiconset/MorrowIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(srgbRed: 0.075, green: 0.165, blue: 0.137, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let sunColor = NSColor(srgbRed: 0.965, green: 0.687, blue: 0.485, alpha: 1)
sunColor.setFill()
NSBezierPath(ovalIn: NSRect(x: 342, y: 504, width: 340, height: 340)).fill()

NSColor(srgbRed: 0.075, green: 0.165, blue: 0.137, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 270, y: 504, width: 484, height: 185)).fill()

sunColor.setStroke()
let rays = NSBezierPath()
rays.lineWidth = 34
rays.lineCapStyle = .round
for (start, end) in [
    (NSPoint(x: 512, y: 850), NSPoint(x: 512, y: 907)),
    (NSPoint(x: 319, y: 780), NSPoint(x: 279, y: 820)),
    (NSPoint(x: 705, y: 780), NSPoint(x: 745, y: 820)),
] {
    rays.move(to: start)
    rays.line(to: end)
}
rays.stroke()

let check = NSBezierPath()
check.move(to: NSPoint(x: 258, y: 472))
check.line(to: NSPoint(x: 430, y: 305))
check.line(to: NSPoint(x: 782, y: 654))
check.lineWidth = 104
check.lineCapStyle = .round
check.lineJoinStyle = .round
sunColor.setStroke()
check.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let cgImage = bitmap.cgImage
else {
    fatalError("Unable to render Morrow app icon")
}

let colorSpace = CGColorSpaceCreateDeviceRGB()
let outputURL = URL(fileURLWithPath: output)
let outputDirectory = outputURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(filename: String, pixels: Int)] = [
    (outputURL.lastPathComponent, 1024),
    ("MorrowIcon-20.png", 20),
    ("MorrowIcon-20@2x.png", 40),
    ("MorrowIcon-20@3x.png", 60),
    ("MorrowIcon-29.png", 29),
    ("MorrowIcon-29@2x.png", 58),
    ("MorrowIcon-29@3x.png", 87),
    ("MorrowIcon-40.png", 40),
    ("MorrowIcon-40@2x.png", 80),
    ("MorrowIcon-40@3x.png", 120),
    ("MorrowIcon-60@2x.png", 120),
    ("MorrowIcon-60@3x.png", 180),
    ("MorrowIcon-76.png", 76),
    ("MorrowIcon-76@2x.png", 152),
    ("MorrowIcon-83.5@2x.png", 167),
]

for variant in variants {
    guard let context = CGContext(
        data: nil,
        width: variant.pixels,
        height: variant.pixels,
        bitsPerComponent: 8,
        bytesPerRow: variant.pixels * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        fatalError("Unable to create opaque CGContext for \(variant.filename)")
    }

    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))

    guard
        let renderedImage = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: renderedImage).representation(
            using: NSBitmapImageRep.FileType.png,
            properties: [:]
        )
    else {
        fatalError("Unable to generate opaque PNG data for \(variant.filename)")
    }

    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
    print("Generated \(variant.filename) at \(variant.pixels)x\(variant.pixels)")
}

