import AppKit

let sourcePath = CommandLine.arguments.dropFirst().first
    ?? "Artwork/QuietListSource.jpg"
let outputPath = CommandLine.arguments.dropFirst(2).first
    ?? "QuietList/Resources/Assets.xcassets/AppIcon.appiconset/QuietListIcon-1024.png"

guard let image = NSImage(contentsOfFile: sourcePath) else {
    fatalError("Unable to read icon artwork at \(sourcePath)")
}

var proposedRect = NSRect(origin: .zero, size: image.size)
guard let sourceImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
    fatalError("Unable to decode icon artwork")
}

let outputURL = URL(fileURLWithPath: outputPath)
let outputDirectory = outputURL.deletingLastPathComponent()
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(filename: String, pixels: Int)] = [
    (outputURL.lastPathComponent, 1024),
    ("QuietListIcon-20.png", 20),
    ("QuietListIcon-20@2x.png", 40),
    ("QuietListIcon-20@3x.png", 60),
    ("QuietListIcon-29.png", 29),
    ("QuietListIcon-29@2x.png", 58),
    ("QuietListIcon-29@3x.png", 87),
    ("QuietListIcon-40.png", 40),
    ("QuietListIcon-40@2x.png", 80),
    ("QuietListIcon-40@3x.png", 120),
    ("QuietListIcon-60@2x.png", 120),
    ("QuietListIcon-60@3x.png", 180),
    ("QuietListIcon-76.png", 76),
    ("QuietListIcon-76@2x.png", 152),
    ("QuietListIcon-83.5@2x.png", 167),
]

let colorSpace = CGColorSpaceCreateDeviceRGB()

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
        fatalError("Unable to create image context for \(variant.filename)")
    }

    context.interpolationQuality = .high
    context.setFillColor(NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.93, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: variant.pixels, height: variant.pixels))

    guard
        let renderedImage = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: renderedImage).representation(using: .png, properties: [:])
    else {
        fatalError("Unable to encode \(variant.filename)")
    }

    try data.write(to: outputDirectory.appendingPathComponent(variant.filename), options: .atomic)
    print("Generated \(variant.filename) at \(variant.pixels)x\(variant.pixels)")
}
