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
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(settings: settings, helper: helper,
                                  monitor: monitor, location: location)
        )

        settings.$showPercentInMenuBar
            .combineLatest(monitor.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateButton()
            }
            .store(in: &cancellables)
        updateButton()
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

    private func updateButton() {
        guard let button = statusItem.button else { return }
        button.image = Self.magSafeIcon()
        button.imagePosition = .imageLeading
        if settings.showPercentInMenuBar, let percent = monitor.state?.percent {
            button.title = " \(percent)%"
        } else {
            button.title = ""
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
            fixPopoverPosition(under: button)
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.statusItem.button else { return }
                self.fixPopoverPosition(under: button)
            }
        }
    }

    /// macOS 26 sometimes places status item popovers too high, overlapping
    /// the menu bar with the arrow pushed off-screen. If that happened, move
    /// the popover window so its top (and arrow) sits right below the icon.
    private func fixPopoverPosition(under button: NSStatusBarButton) {
        guard let popWindow = popover.contentViewController?.view.window,
              let iconWindow = button.window else { return }
        let icon = iconWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var frame = popWindow.frame
        guard frame.maxY > icon.minY else { return } // already placed correctly

        frame.origin.y = icon.minY - frame.height
        frame.origin.x = icon.midX - frame.width / 2
        if let screen = iconWindow.screen ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX + 4),
                                 screen.visibleFrame.maxX - frame.width - 4)
        }
        popWindow.setFrame(frame, display: true)
    }
}
