// Renders the MagHue app icon: a MagSafe connector with a green LED.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Rounded-square background, dark slate gradient.
let inset: CGFloat = size * 0.08
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.18, yRadius: size * 0.18)
bgPath.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1),
])
gradient?.draw(in: bgRect, angle: -90)

// MagSafe connector body: a wide silver pill.
let pillWidth = size * 0.56
let pillHeight = size * 0.20
let pillRect = CGRect(x: (size - pillWidth) / 2,
                      y: (size - pillHeight) / 2,
                      width: pillWidth, height: pillHeight)
let pill = NSBezierPath(roundedRect: pillRect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)
NSGradient(colors: [
    NSColor(calibratedWhite: 0.88, alpha: 1),
    NSColor(calibratedWhite: 0.62, alpha: 1),
])?.draw(in: pill, angle: -90)

// Cable stub leaving the connector.
let cableWidth = size * 0.05
let cableRect = CGRect(x: pillRect.minX - size * 0.14,
                       y: size / 2 - cableWidth / 2,
                       width: size * 0.15, height: cableWidth)
NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
NSBezierPath(roundedRect: cableRect, xRadius: cableWidth / 2, yRadius: cableWidth / 2).fill()

// The LED, glowing green.
let ledRadius = size * 0.045
let ledCenter = CGPoint(x: pillRect.maxX - pillHeight * 0.55, y: size / 2)
let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.45, alpha: 0.85),
    NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.45, alpha: 0.0),
])
let glowRect = CGRect(x: ledCenter.x - ledRadius * 4, y: ledCenter.y - ledRadius * 4,
                      width: ledRadius * 8, height: ledRadius * 8)
glow?.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

NSColor(calibratedRed: 0.25, green: 0.90, blue: 0.40, alpha: 1).setFill()
NSBezierPath(ovalIn: CGRect(x: ledCenter.x - ledRadius, y: ledCenter.y - ledRadius,
                            width: ledRadius * 2, height: ledRadius * 2)).fill()

ctx.flush()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
