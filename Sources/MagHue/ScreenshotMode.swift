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

    /// The directory to write into, if `--screenshot <directory>` was passed.
    static func requestedDirectory() -> URL? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--screenshot") else { return nil }
        let path = args.indices.contains(flag + 1) ? args[flag + 1] : "docs"
        isActive = true
        return URL(fileURLWithPath: path)
    }

    /// Runs the capture inside the normal app lifecycle: the shots are taken
    /// from a real, active, key window, so controls draw in their accent
    /// colours instead of the greys AppKit uses for inactive windows.
    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let helper = HelperManager()
        let settings = Settings(helper: helper)
        let monitor = BatteryMonitor(settings: settings)
        let location = LocationProvider()

        capture(PopoverView(settings: settings, helper: helper, monitor: monitor,
                            location: location),
                to: directory.appendingPathComponent("popover-light.png")) {
            // A sample rule for the Automation tab: light off from sunset to
            // sunrise on weekdays. The coordinates only stop the "needs
            // location" note appearing; they never reach the config file here.
            settings.setLocation(latitude: 42.70, longitude: 23.32)
            settings.schedules = [
                Schedule(days: [2, 3, 4, 5, 6], start: .sunset, end: .sunrise, action: .off)
            ]
            capture(PopoverView(settings: settings, helper: helper, monitor: monitor,
                                location: location, initialTab: .automation),
                    to: directory.appendingPathComponent("popover-automation.png")) {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Rendering

    /// Draws a view through a real window so the AppKit-backed controls —
    /// sliders, segmented pickers, switches — come out as they look in the
    /// app, then mats the result on a soft rounded backdrop.
    private static func capture(_ view: some View, to url: URL,
                                then next: @escaping () -> Void) {
        // The view is drawn in a window of its own rather than in a popover: a
        // popover's window refuses key status, and AppKit draws the controls
        // inside a window that isn't key in their inactive greys — switches
        // come out grey instead of blue. The size is the same either way,
        // because StatusItemController gives its hosting controller
        // `sizingOptions = [.preferredContentSize]`, which is exactly the
        // fitting size used here.
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let window = KeyableWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        window.contentView = hosting
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.ignoresMouseEvents = true
        // On screen (AppKit won't make an offscreen window key) but invisible.
        window.alphaValue = 0.01
        if let visible = NSScreen.main?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: visible.minX + 20, y: visible.minY + 20))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Let SwiftUI settle: layout, preference updates, the battery read.
        after(1.0) {
            window.setContentSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            after(0.4) {
                print("captured \(hosting.bounds.size) key=\(window.isKeyWindow)")
                guard let shot = bitmap(of: hosting) else {
                    FileHandle.standardError.write(Data("could not create bitmap\n".utf8))
                    return next()
                }
                window.orderOut(nil)
                write(matted(shot), to: url)
                next()
            }
        }
    }

    /// Renders the view's layer tree. `cacheDisplay(in:to:)` misses controls
    /// whose tint lives in private sublayers — the schedule switch came out
    /// grey — so go through Core Animation instead.
    private static func bitmap(of view: NSView) -> NSImage? {
        let bounds = view.bounds
        let scale = view.window?.backingScaleFactor ?? 2
        guard let layer = view.layer,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        // Point size first: the context takes its scale from the rep's size.
        rep.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let cg = context.cgContext
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        // Core Animation draws top-down; the bitmap context is bottom-up.
        cg.translateBy(x: 0, y: bounds.height)
        cg.scaleBy(x: 1, y: -1)
        layer.render(in: cg)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
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

/// A borderless window refuses key status by default, and a window that isn't
/// key draws its controls untinted — which is what turned the schedule switch
/// grey in the first round of screenshots.
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Delegate used only by `--screenshot`: renders the images, then quits.
final class ScreenshotDelegate: NSObject, NSApplicationDelegate {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        ScreenshotMode.run(into: directory)
    }
}
