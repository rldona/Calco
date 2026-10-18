// Draws the repository cover (GitHub social preview and README banner): the app icon, the name and
// the tagline on Calco's dark Estudio background with its amber accent.
// Run from the repo root: swift scripts/make-cover.swift  →  Assets/cover.png (1280x640)
import AppKit
import CoreGraphics
import CoreText
import Foundation

let width = 1280, height = 640
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: the editor's near-black, with a soft amber glow behind the icon.
ctx.setFillColor(rgb(0x1C1C1E)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [rgb(0xEF9F27, 0.28), rgb(0xEF9F27, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 320), startRadius: 0,
                       endCenter: CGPoint(x: 330, y: 320), endRadius: 360, options: [])

// Faint exposure-sheet cells along the bottom, like the timeline.
for i in 0..<22 {
    let x = 70 + CGFloat(i) * 52
    let cell = CGRect(x: x, y: 56, width: 44, height: 26)
    let path = CGPath(roundedRect: cell, cornerWidth: 5, cornerHeight: 5, transform: nil)
    ctx.addPath(path)
    ctx.setStrokeColor(i == 7 ? rgb(0xEF9F27, 0.9) : rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(i == 7 ? 2.5 : 1.5)
    ctx.strokePath()
}

// The icon, rounded like on the home screen, with a drop shadow.
guard let iconImage = NSImage(contentsOfFile: "Calco/Assets.xcassets/AppIcon.appiconset/AppIcon.png"),
      let icon = iconImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("icon not found") }
let iconRect = CGRect(x: 160, y: 150, width: 340, height: 340)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x000000, 0.55))
ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 76, cornerHeight: 76, transform: nil))
ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: iconRect, cornerWidth: 76, cornerHeight: 76, transform: nil))
ctx.clip()
ctx.draw(icon, in: iconRect)
ctx.restoreGState()

// Text.
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, at point: CGPoint, kern: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: kern]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    ctx.textPosition = point
    CTLineDraw(line, ctx)
}

draw("Calco", size: 150, weight: .bold, color: rgb(0xF1EFE8), at: CGPoint(x: 560, y: 340), kern: -3)
draw("Hand-drawn sprite animation", size: 40, weight: .medium, color: rgb(0xFAC775), at: CGPoint(x: 566, y: 270))
draw("for iPad and Apple Pencil, built for game engines", size: 28, weight: .regular,
     color: rgb(0xF1EFE8, 0.72), at: CGPoint(x: 566, y: 222))
draw("Unity · Godot · Sprite sheets · Open source", size: 22, weight: .medium,
     color: rgb(0xF1EFE8, 0.45), at: CGPoint(x: 566, y: 172), kern: 0.5)

let out = URL(fileURLWithPath: "Assets/cover.png")
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote", out.path)
