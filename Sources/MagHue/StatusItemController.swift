import AppKit
import Combine
import MagHueCore
import SwiftUI

/// Owns the menu bar item and the popover that hosts the SwiftUI interface.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let settings: Settings
    private let helper: HelperManager
    private let monitor: BatteryMonitor
    private let location: LocationProvider
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings, helper: HelperManager, monitor: BatteryMonitor,
         location: LocationProvider) {
        self.settings = settings
        self.helper = helper
        self.monitor = monitor
        self.location = location
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.image = Self.magSafeIcon()
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(
            rootView: PopoverView(settings: settings, helper: helper,
                                  monitor: monitor, location: location)
        )
        // Without this the controller never reports a preferred size, so the
        // popover stays at its default 320pt height and the content has to
        // scroll. With it, the popover grows and shrinks to fit the interface.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        // MagHue's own item is a fixed-width icon, but the ones around it come
        // and go, which shifts ours along the bar. Follow it immediately, on
        // every step of the move, so an open popover stays attached to it.
        NotificationCenter.default
            .publisher(for: NSWindow.didMoveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification))
            .compactMap { $0.object as? NSWindow }
            .filter { [weak self] window in window === self?.statusItem.button?.window }
            .sink { [weak self] _ in
                guard let self, self.popover.isShown,
                      let button = self.statusItem.button else { return }
                self.placePopover(under: button)
            }
            .store(in: &cancellables)

        // Opening the popover activates MagHue, so switching to any other app
        // means the user is done with it — close it rather than leaving it
        // floating over their work. `.transient` alone doesn't cover this.
        NotificationCenter.default
            .publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
            .store(in: &cancellables)
    }

    private static func magSafeIcon() -> NSImage? {
        for symbol in ["magsafe.batterypack", "bolt.badge.checkmark", "bolt.circle"] {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MagHue") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    /// Places the popover as it opens, before it's on screen, so there's
    /// nothing to see: once immediately and once on the next pass of the run
    /// loop, after AppKit has had its own go at positioning it.
    private func anchorPopoverUnderStatusItem() {
        guard let button = statusItem.button else { return }
        placePopover(under: button)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown,
                  let button = self.statusItem.button else { return }
            self.placePopover(under: button)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            helper.refresh()
            monitor.refresh()
            settings.syncFromDisk()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
            anchorPopoverUnderStatusItem()
        }
    }

    /// Puts the popover directly under the status item.
    ///
    /// macOS 26 sometimes places status item popovers too high, overlapping
    /// the menu bar with the arrow pushed off-screen, so MagHue positions it
    /// itself. The placement is absolute rather than a nudge: it is worked out
    /// from the icon's current position every time, so repeated calls always
    /// land in the same place instead of accumulating an offset.
    private func placePopover(under button: NSStatusBarButton) {
        guard let popWindow = popover.contentViewController?.view.window,
              let iconWindow = button.window else { return }
        let icon = iconWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var frame = popWindow.frame

        frame.origin.y = icon.minY - frame.height
        frame.origin.x = icon.midX - frame.width / 2
        if let screen = iconWindow.screen ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX + 4),
                                 screen.visibleFrame.maxX - frame.width - 4)
        }
        guard frame != popWindow.frame else { return }
        popWindow.setFrame(frame, display: true)
    }
}
