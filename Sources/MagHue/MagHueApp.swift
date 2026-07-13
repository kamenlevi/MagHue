import AppKit

@main
enum MagHueMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock icon, no app switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var helper: HelperManager!
    private var settings: Settings!
    private var monitor: BatteryMonitor!
    private var statusItemController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        helper = HelperManager()
        settings = Settings(helper: helper)
        monitor = BatteryMonitor(settings: settings)
        statusItemController = StatusItemController(settings: settings,
                                                    helper: helper,
                                                    monitor: monitor)
        // Make sure the helper's config matches the app's settings on launch.
        settings.pushToHelper()
        if settings.notifyOnThreshold {
            monitor.requestNotificationPermission()
        }
    }
}
