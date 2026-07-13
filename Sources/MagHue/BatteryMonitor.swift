import Combine
import Foundation
import IOKit.ps
import MagHueCore
import UserNotifications

/// App-side battery watcher: drives the menu bar percentage and the optional
/// threshold notification. LED changes are the helper's job, not ours.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var state: BatteryState?

    private let settings: Settings
    private var timer: Timer?
    private var wasAboveThreshold = false
    private var notificationsReady = false

    init(settings: Settings) {
        self.settings = settings
        state = Battery.read()
        wasAboveThreshold = aboveThreshold(state)

        let callback: IOPowerSourceCallbackType = { context in
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.refresh()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let fresh = Battery.read()
        let above = aboveThreshold(fresh)
        if settings.notifyOnThreshold, above, !wasAboveThreshold {
            postThresholdNotification(percent: fresh?.percent ?? settings.threshold)
        }
        wasAboveThreshold = above
        if fresh != state {
            state = fresh
        }
    }

    private func aboveThreshold(_ state: BatteryState?) -> Bool {
        guard let state, state.onACPower else { return false }
        return state.percent >= settings.threshold
    }

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil, !notificationsReady else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                self?.notificationsReady = granted
            }
    }

    private func postThresholdNotification(percent: Int) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = "MagSafe LED is green"
        content.body = "Battery reached \(percent)% — at or above your \(settings.threshold)% threshold."
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
