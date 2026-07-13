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
        showPercentInMenuBar = defaults.bool(forKey: "showPercentInMenuBar")
        notifyOnThreshold = defaults.bool(forKey: "notifyOnThreshold")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var helperConfig: HelperConfig {
        HelperConfig(mode: mode, threshold: threshold)
    }

    func pushToHelper() {
        helper.write(config: helperConfig)
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
