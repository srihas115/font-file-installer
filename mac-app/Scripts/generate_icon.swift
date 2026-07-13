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

// Wordmark: "FONT" / "INSTALLER" stacked, bold rounded, centered.
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let lines = [
    (text: "FONT", size: iconRect.width * 0.185),
    (text: "INSTALLER", size: iconRect.width * 0.098),
]

let lineSpacing = iconRect.width * 0.045
var renderedLines: [(image: NSImage, size: NSSize)] = []
var totalHeight: CGFloat = 0

for line in lines {
    let font = NSFont.systemFont(ofSize: line.size, weight: .heavy).withRoundedDesignIfAvailable()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle,
        .kern: line.size * 0.02,
    ]
    let attributedString = NSAttributedString(string: line.text, attributes: attributes)
    let lineSize = attributedString.size()

    let lineImage = NSImage(size: lineSize)
    lineImage.lockFocus()
    attributedString.draw(at: .zero)
    lineImage.unlockFocus()

    renderedLines.append((lineImage, lineSize))
    totalHeight += lineSize.height
}
totalHeight += lineSpacing * CGFloat(renderedLines.count - 1)

var currentY = iconRect.midY + totalHeight / 2
for (lineImage, lineSize) in renderedLines {
    currentY -= lineSize.height
    let origin = CGPoint(x: iconRect.midX - lineSize.width / 2, y: currentY)
    lineImage.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    currentY -= lineSpacing
}

extension NSFont {
    func withRoundedDesignIfAvailable() -> NSFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
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
