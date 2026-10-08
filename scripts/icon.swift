import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let bounds = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let rect = bounds.insetBy(dx: Double(pixels) * 0.06, dy: Double(pixels) * 0.06)
        let path = NSBezierPath(roundedRect: rect, xRadius: Double(pixels) * 0.21, yRadius: Double(pixels) * 0.21)
        NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.27, alpha: 1),
                   ending: NSColor(calibratedRed: 0.03, green: 0.08, blue: 0.13, alpha: 1))!.draw(in: path, angle: 90)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: Double(pixels) * 0.57, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0.4, green: 0.94, blue: 0.76, alpha: 1)
        ]
        let text = NSAttributedString(string: "⌘", attributes: attributes)
        let textSize = text.size()
        text.draw(at: NSPoint(x: (Double(pixels) - textSize.width) / 2, y: (Double(pixels) - textSize.height) / 2))
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c","icns",iconset.path,"-o",output.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
try FileManager.default.removeItem(at: iconset)
