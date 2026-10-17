// Renders assets/brand/social-preview.png (1280×640), the image GitHub shows when the
// repository link is shared. Upload it once: Settings → General → Social preview.
//
//   swift scripts/make-social-preview.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let size = NSSize(width: 1280, height: 640)
let image = NSImage(size: size)
image.lockFocus()

// Background: the product page's night-blue gradient with a warm glow behind the tip.
NSGradient(colors: [NSColor(srgbRed: 0.15, green: 0.20, blue: 0.43, alpha: 1), NSColor(srgbRed: 0.05, green: 0.07, blue: 0.14, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -30)
NSGradient(colors: [NSColor(srgbRed: 1, green: 0.35, blue: 0.31, alpha: 0.30), .clear])!
    .draw(fromCenter: NSPoint(x: 1000, y: 300), radius: 0, toCenter: NSPoint(x: 1000, y: 300), radius: 360, options: [])

if let icon = NSImage(contentsOf: root.appendingPathComponent("assets/brand/app-icon-1024.png")) {
    icon.draw(in: NSRect(x: 72, y: 418, width: 150, height: 150))
}
func draw(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let style = NSMutableParagraphStyle()
    style.lineHeightMultiple = 1.05
    let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
    // y is the bottom of the text block (AppKit coordinates grow upwards).
    let height = ceil(string.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]).height)
    string.draw(with: NSRect(x: x, y: y, width: width, height: height), options: [.usesLineFragmentOrigin])
}
draw("Saidright", x: 80, y: 308, width: 640, size: 84, weight: .bold, color: .white)
draw("Dictation that teaches you\nthe language you speak", x: 80, y: 168, width: 660, size: 44, weight: .semibold, color: NSColor(white: 1, alpha: 0.92))
draw("Free · open source · runs on your Mac", x: 80, y: 104, width: 660, size: 26, weight: .regular, color: NSColor(white: 1, alpha: 0.62))

if let tip = NSImage(contentsOf: root.appendingPathComponent("docs/screenshots/readme-tip.png")) {
    let width: CGFloat = 470
    let height = width * tip.size.height / tip.size.width
    tip.draw(in: NSRect(x: 760, y: (640 - height) / 2, width: width, height: height))
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let out = root.appendingPathComponent("assets/brand/social-preview.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
