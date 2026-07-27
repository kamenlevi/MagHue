import AppKit
import MagHueCore
import SwiftUI

/// Renders the popover to PNGs for the README:
///
///     MagHue.app/Contents/MacOS/MagHue --screenshot docs
///
/// The app draws its own interface into an offscreen bitmap, so this needs no
/// screen-recording permission. While it's active nothing is written back to
/// UserDefaults or the helper's config file — see `Settings.pushToHelper()`.
enum ScreenshotMode {
    /// True while the app is rendering README images rather than running.
    private(set) static var isActive = false

    /// Runs the screenshot pass if `--screenshot <directory>` was passed, and
    /// returns true if it did (in which case the app should not start up).
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--screenshot") else { return false }
        let directory = args.indices.contains(flag + 1) ? args[flag + 1] : "docs"
        isActive = true
        run(into: URL(fileURLWithPath: directory))
        return true
    }

    private static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let helper = HelperManager()
        let settings = Settings(helper: helper)
        let monitor = BatteryMonitor(settings: settings)
        let location = LocationProvider()

        capture(PopoverView(settings: settings, helper: helper, monitor: monitor,
                            location: location),
                to: directory.appendingPathComponent("popover-light.png"))

        // A sample rule for the Automation tab: light off from sunset to
        // sunrise on weekdays. The coordinates only stop the "needs location"
        // note from appearing; they never reach the config file here.
        settings.setLocation(latitude: 42.70, longitude: 23.32)
        settings.schedules = [
            Schedule(days: [2, 3, 4, 5, 6], start: .sunset, end: .sunrise, action: .off)
        ]
        capture(PopoverView(settings: settings, helper: helper, monitor: monitor,
                            location: location, initialTab: .automation),
                to: directory.appendingPathComponent("popover-automation.png"))
    }

    // MARK: - Rendering

    /// Draws a view through a real (offscreen) window so the AppKit-backed
    /// controls — sliders, segmented pickers, checkboxes — come out as they
    /// look in the app, then mats the result on a soft rounded backdrop.
    private static func capture(_ view: some View, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.alphaValue = 0            // present but invisible while it lays out
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        // Key + active, or AppKit draws every control in its inactive grey.
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let SwiftUI settle: layout, preference updates, the battery read.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)

        let shot = NSImage(size: hosting.bounds.size)
        shot.addRepresentation(rep)
        write(matted(shot), to: url)
    }

    /// Puts the popover on a padded backdrop with rounded corners and a soft
    /// shadow, so the image looks like a screenshot rather than a raw slab.
    private static func matted(_ image: NSImage) -> NSImage {
        let inset: CGFloat = 28
        let size = NSSize(width: image.size.width + inset * 2,
                          height: image.size.height + inset * 2)
        let canvas = NSImage(size: size)
        canvas.lockFocusFlipped(false)

        // Backdrop follows the appearance the interface was drawn in.
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let backdrop = isDark
            ? [NSColor(calibratedWhite: 0.16, alpha: 1), NSColor(calibratedWhite: 0.09, alpha: 1)]
            : [NSColor(calibratedWhite: 0.95, alpha: 1), NSColor(calibratedWhite: 0.87, alpha: 1)]
        NSGradient(colors: backdrop)?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

        let frame = NSRect(x: inset, y: inset,
                           width: image.size.width, height: image.size.height)
        let rounded = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        rounded.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        rounded.addClip()
        image.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()

        canvas.unlockFocus()
        return canvas
    }

    private static func write(_ image: NSImage, to url: URL) {
        // Redraw at 2x so the PNG is retina-sharp in the README.
        let pixels = NSSize(width: image.size.width * 2, height: image.size.height * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
            print("wrote \(url.path) (\(Int(pixels.width))×\(Int(pixels.height)))")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
        }
    }
}
