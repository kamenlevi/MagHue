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
    /// Set when the menu bar item wants redrawing but the popover is open.
    private var buttonNeedsUpdate = false

    init(settings: Settings, helper: HelperManager, monitor: BatteryMonitor,
         location: LocationProvider) {
        self.settings = settings
        self.helper = helper
        self.monitor = monitor
        self.location = location
        // Variable length: a square item is too narrow for the percentage
        // text, which then wraps into a column of digits.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = true
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

        settings.$showPercentInMenuBar
            .combineLatest(monitor.$state)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateButton()
            }
            .store(in: &cancellables)
        updateButton()

        // The status item's window moves when the item's width changes, so
        // that's the cue to put the popover back under the icon. The menu bar
        // shuffles the item through intermediate positions on the way, though,
        // so wait for it to stop moving and follow once, rather than chasing
        // every step and juddering across the screen.
        NotificationCenter.default
            .publisher(for: NSWindow.didMoveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification))
            .compactMap { $0.object as? NSWindow }
            .filter { [weak self] window in window === self?.statusItem.button?.window }
            .debounce(for: .milliseconds(120), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.popover.isShown,
                      let button = self.statusItem.button else { return }
                self.placePopover(under: button, animated: true)
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

    private func updateButton() {
        guard let button = statusItem.button else { return }
        // Changing the title resizes the status item, which moves the icon —
        // and the popover hanging off it. Rather than have it slide about
        // while the user is working in it (toggling the percentage, or the
        // battery simply ticking over), hold the change until it closes.
        guard !popover.isShown else {
            buttonNeedsUpdate = true
            return
        }
        buttonNeedsUpdate = false
        button.image = Self.magSafeIcon()
        button.imagePosition = .imageLeading
        if settings.showPercentInMenuBar, let percent = monitor.state?.percent {
            button.attributedTitle = NSAttributedString(
                string: " \(percent)%",
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(
                        ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
                ]
            )
            statusItem.length = NSStatusItem.variableLength
        } else {
            button.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if buttonNeedsUpdate {
            updateButton()
        }
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
    private func placePopover(under button: NSStatusBarButton, animated: Bool = false) {
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
        if animated {
            // Following the icon after the bar resizes: slide, so it reads as
            // the popover keeping up rather than snapping about.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                popWindow.animator().setFrame(frame, display: true)
            }
        } else {
            popWindow.setFrame(frame, display: true)
        }
    }
}
