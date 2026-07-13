import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and the popover that hosts the SwiftUI interface.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let settings: Settings
    private let helper: HelperManager
    private let monitor: BatteryMonitor
    private var cancellables: Set<AnyCancellable> = []

    init(settings: Settings, helper: HelperManager, monitor: BatteryMonitor) {
        self.settings = settings
        self.helper = helper
        self.monitor = monitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(settings: settings, helper: helper, monitor: monitor)
        )

        settings.$showPercentInMenuBar
            .combineLatest(monitor.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showPercent, state in
                self?.updateTitle(showPercent: showPercent, percent: state?.percent)
            }
            .store(in: &cancellables)
    }

    private static func menuBarIcon() -> NSImage? {
        for symbol in ["magsafe.batterypack", "bolt.badge.checkmark", "bolt.circle"] {
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MagHue") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    private func updateTitle(showPercent: Bool, percent: Int?) {
        if showPercent, let percent {
            statusItem.button?.title = " \(percent)%"
        } else {
            statusItem.button?.title = ""
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            helper.refresh()
            monitor.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
