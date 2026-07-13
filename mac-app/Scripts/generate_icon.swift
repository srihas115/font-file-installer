import AppKit

let size = 1024
let canvas = NSImage(size: NSSize(width: size, height: size))

canvas.lockFocus()

let context = NSGraphicsContext.current!.cgContext

// macOS Big Sur+ icons live inside a rounded square with ~10% padding on each side.
let inset = CGFloat(size) * 0.05
let iconRect = CGRect(x: inset, y: inset, width: CGFloat(size) - inset * 2, height: CGFloat(size) - inset * 2)
let cornerRadius = iconRect.width * 0.225

let path = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.98, alpha: 1.0),
    NSColor(calibratedRed: 0.62, green: 0.35, blue: 0.92, alpha: 1.0),
])!
path.addClip()
gradient.draw(in: iconRect, angle: -60)

// Glyph: bold "Aa" to read as "fonts" at a glance.
let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconRect.width * 0.52, weight: .bold)
if let symbol = NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let imageRect = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: imageRect)
    imageRect.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let glyphSize = tinted.size
    let glyphOrigin = CGPoint(
        x: iconRect.midX - glyphSize.width / 2,
        y: iconRect.midY - glyphSize.height / 2
    )
    tinted.draw(at: glyphOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)
}

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render icon")
}

let outputPath = CommandLine.arguments[1]
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
_ = context
