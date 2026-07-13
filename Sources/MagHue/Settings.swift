import Combine
import Foundation
import MagHueCore
import ServiceManagement

/// User preferences. LED-related values are mirrored into the helper's config
/// file whenever they change; the rest only affect the app.
final class Settings: ObservableObject {
    @Published var mode: LEDMode {
        didSet { defaults.set(mode.rawValue, forKey: "mode"); pushToHelper() }
    }
    @Published var threshold: Int {
        didSet { defaults.set(threshold, forKey: "threshold"); pushToHelper() }
    }
    /// One-shot Charge to Full. Lives in the helper's config file (not
    /// UserDefaults) because the helper clears it itself when the battery
    /// fills up; `syncFromDisk()` picks that up.
    @Published var chargeToFull: Bool {
        didSet { if chargeToFull != oldValue { pushToHelper() } }
    }
    @Published var showPercentInMenuBar: Bool {
        didSet { defaults.set(showPercentInMenuBar, forKey: "showPercentInMenuBar") }
    }
    @Published var notifyOnThreshold: Bool {
        didSet { defaults.set(notifyOnThreshold, forKey: "notifyOnThreshold") }
    }
    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }
    @Published var launchAtLoginError: String?

    private let defaults = UserDefaults.standard
    let helper: HelperManager

    init(helper: HelperManager) {
        self.helper = helper
        mode = LEDMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .auto
        let stored = defaults.integer(forKey: "threshold")
        threshold = stored == 0 ? 80 : stored
        chargeToFull = HelperConfig.load().chargeToFull
        showPercentInMenuBar = defaults.bool(forKey: "showPercentInMenuBar")
        notifyOnThreshold = defaults.bool(forKey: "notifyOnThreshold")

        // Launch at login defaults to on: register it the first time the app
        // runs, then respect whatever the user chooses afterwards.
        if !defaults.bool(forKey: "didSetInitialLaunchAtLogin") {
            defaults.set(true, forKey: "didSetInitialLaunchAtLogin")
            try? SMAppService.mainApp.register()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var helperConfig: HelperConfig {
        HelperConfig(mode: mode, threshold: threshold, chargeToFull: chargeToFull)
    }

    func pushToHelper() {
        helper.write(config: helperConfig)
    }

    /// Picks up changes the helper made to the config file, e.g. clearing
    /// the Charge to Full flag once the battery reached 100%.
    func syncFromDisk() {
        let onDisk = HelperConfig.load().chargeToFull
        if onDisk != chargeToFull {
            chargeToFull = onDisk
        }
    }

    private func applyLaunchAtLogin() {
        guard Bundle.main.bundleIdentifier != nil else {
            launchAtLoginError = "Run the built app bundle to use launch at login."
            return
        }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
    }
}
