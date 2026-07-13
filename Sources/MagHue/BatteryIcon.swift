import AppKit
import MagHueCore

/// Draws an iPhone-style battery for the menu bar: translucent body, colored
/// fill proportional to charge, terminal nub, and a bolt while on power.
enum BatteryIcon {
    static func render(percent: Int, fill: NSColor, bolt: Bool) -> NSImage {
        let size = NSSize(width: 27, height: 13)
        let image = NSImage(size: size, flipped: false) { _ in
            let track = NSColor(white: 0.5, alpha: 0.6)

            let bodyRect = NSRect(x: 0, y: 1, width: 23, height: 11)
            track.setFill()
            NSBezierPath(roundedRect: bodyRect, xRadius: 3.5, yRadius: 3.5).fill()

            let nubRect = NSRect(x: 23.7, y: 4.5, width: 2.6, height: 4)
            track.setFill()
            NSBezierPath(roundedRect: nubRect, xRadius: 1.3, yRadius: 1.3).fill()

            let inset: CGFloat = 1.5
            let clamped = CGFloat(min(max(percent, 0), 100))
            let maxWidth = bodyRect.width - inset * 2
            let fillRect = NSRect(x: bodyRect.minX + inset,
                                  y: bodyRect.minY + inset,
                                  width: max(2.5, maxWidth * clamped / 100),
                                  height: bodyRect.height - inset * 2)
            fill.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2.2, yRadius: 2.2).fill()

            if bolt {
                let boltSize = NSSize(width: 7, height: 9)
                let boltRect = NSRect(x: bodyRect.midX - boltSize.width / 2,
                                      y: bodyRect.midY - boltSize.height / 2,
                                      width: boltSize.width, height: boltSize.height)
                tintedBolt()?.draw(in: boltRect)
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func tintedBolt() -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "bolt.fill",
                                   accessibilityDescription: nil) else { return nil }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            NSColor.white.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        return tinted
    }

    /// The iOS status bar color for this battery state, or nil for the
    /// neutral state (which uses the standard template icon so it adapts to
    /// the menu bar appearance the way iOS's white does to its status bar).
    static func iphoneColor(for state: BatteryState?, lowPowerMode: Bool) -> NSColor? {
        guard let state else { return nil }
        if lowPowerMode { return .systemYellow }
        if state.onACPower { return .systemGreen }
        if state.percent <= 20 { return .systemRed }
        return nil
    }
}
