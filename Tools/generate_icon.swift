import AppKit
import ImageIO
guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate_icon.swift <iconset directory> <output.icns>\n", stderr)
    exit(1)
}
let output = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)
for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let size = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size), inset = s * 0.045
    let path = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2), xRadius: s*0.23, yRadius: s*0.23)
    NSGradient(starting: NSColor(calibratedRed: 0.25, green: 0.65, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.32, blue: 0.87, alpha: 1))!.draw(in: path, angle: 65)
    NSColor.white.withAlphaComponent(0.5).setStroke(); path.lineWidth = max(1, s*0.008); path.stroke()
    let bubble = NSBezierPath(roundedRect: NSRect(x: s*0.21, y: s*0.26, width: s*0.59, height: s*0.49), xRadius: s*0.115, yRadius: s*0.115)
    NSGradient(starting: NSColor.white.withAlphaComponent(0.98), ending: NSColor.white.withAlphaComponent(0.70))!.draw(in: bubble, angle: -90)
    let tail = NSBezierPath(); tail.move(to: NSPoint(x:s*0.31,y:s*0.30));tail.line(to:NSPoint(x:s*0.31,y:s*0.18));tail.line(to:NSPoint(x:s*0.47,y:s*0.30));tail.close()
    NSColor.white.withAlphaComponent(0.75).setFill(); tail.fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s*0.33, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.38, blue: 0.87, alpha: 1)]
    let text = "あ" as NSString, textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (s-textSize.width)/2, y: s*0.5-textSize.height/2+s*0.03), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}

// ICNS is a big-endian container of typed image chunks. Store modern PNG
// representations directly so builds do not depend on iconutil's conversion service.
func word(_ value: Int) -> Data {
    var bigEndian = UInt32(value).bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}
let representations = [
    ("icp4", "16x16"), ("ic11", "16x16@2x"),
    ("icp5", "32x32"), ("ic12", "32x32@2x"),
    ("ic07", "128x128"), ("ic13", "128x128@2x"),
    ("ic08", "256x256"), ("ic14", "256x256@2x"),
    ("ic09", "512x512"), ("ic10", "512x512@2x")
]
var chunks = Data()
for (type, size) in representations {
    let png = try Data(contentsOf: URL(fileURLWithPath: output).appendingPathComponent("icon_\(size).png"))
    chunks.append(Data(type.utf8)); chunks.append(word(png.count + 8)); chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(word(chunks.count + 8)); icon.append(chunks)
guard let source = CGImageSourceCreateWithData(icon as CFData, nil),
      CGImageSourceGetCount(source) >= representations.count,
      CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
    fputs("Generated icon failed ImageIO validation.\n", stderr)
    exit(1)
}
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
