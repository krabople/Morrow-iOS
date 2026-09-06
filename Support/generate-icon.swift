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
guard let cgContext = CGContext(
    data: nil,
    width: 1024,
    height: 1024,
    bitsPerComponent: 8,
    bytesPerRow: 1024 * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fatalError("Unable to create opaque CGContext")
}

cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))

guard
    let opaqueCgImage = cgContext.makeImage(),
    let data = NSBitmapImageRep(cgImage: opaqueCgImage).representation(using: NSBitmapImageRep.FileType.png, properties: [:])
else {
    fatalError("Unable to generate opaque PNG data")
}

let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL, options: Data.WritingOptions.atomic)
print("Generated opaque icon at \(outputURL.path)")

