// Deliberately no `import AppKit` here. On the macOS 27 SDK it shadows
// SwiftUI's State, which stops @State being a property wrapper at all: `$tab`
// vanishes and assigning to a @State property reads as mutating the view.
// SwiftUI re-exports what this file needs from AppKit anyway (NSWorkspace,
// NSApp, NSColor), and the wrappers below are qualified so no future import
// can shadow them either.
import MagHueCore
import SwiftUI

struct PopoverView: View {
    /// PayPal donation link. The account (`DHQUELMQRQW46`) is Peter Levi's,
    /// the same one Variety collects donations through; only the item name
    /// differs, so a donation made here is recorded against MagHue.
    private static let donateURL = URL(string:
        "https://www.paypal.com/donate/?business=DHQUELMQRQW46&no_recurring=0"
        + "&item_name=MagHue&currency_code=EUR")!

    @SwiftUI.ObservedObject var settings: Settings
    @SwiftUI.ObservedObject var helper: HelperManager
    @SwiftUI.ObservedObject var monitor: BatteryMonitor
    @SwiftUI.ObservedObject var location: LocationProvider
    @SwiftUI.State private var systemChargeStatus: String?
    @SwiftUI.State private var tab: Tab

    enum Tab: Hashable { case light, automation }

    // Spelled out rather than inferred from the binding: Swift 6.4 resolves
    // the picker's generic to `any Hashable` when these are written inline,
    // and then `.light` and `.automation` don't exist on it. Fails the build
    // on the macOS 27 SDK; harmless everywhere else.
    private static let tabOptions: [SegmentedPicker<Tab>.Option] = [
        SegmentedPicker<Tab>.Option(.light, "Light"),
        SegmentedPicker<Tab>.Option(.automation, "Automation"),
    ]

    private static let modeOptions: [SegmentedPicker<LEDMode>.Option] = [
        SegmentedPicker<LEDMode>.Option(.auto, "Custom"),
        SegmentedPicker<LEDMode>.Option(.off, "Off"),
        SegmentedPicker<LEDMode>.Option(.system, "System"),
    ]

    init(settings: Settings, helper: HelperManager, monitor: BatteryMonitor,
         location: LocationProvider, initialTab: Tab = .light) {
        self.settings = settings
        self.helper = helper
        self.monitor = monitor
        self.location = location
        _tab = SwiftUI.State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if helper.isInstalled {
                SegmentedPicker(selection: $tab, options: Self.tabOptions)

                switch tab {
                case .light:
                    controls
                    Divider()
                    options
                case .automation:
                    automation
                }

                if helper.needsUpdate {
                    updatePrompt
                }
            } else {
                installPrompt
            }

            if let error = helper.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            ledDot
            VStack(alignment: .leading, spacing: 1) {
                Text("MagHue").font(.headline)
                Text(batteryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            donateButton
        }
    }

    /// Sits across from the title: small enough to ignore, clear enough to
    /// find. Opens the PayPal page in the browser.
    private var donateButton: some View {
        Button {
            NSWorkspace.shared.open(Self.donateURL)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.pink)
                Text("Donate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Support MagHue with a donation")
    }

    private var installPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MagHue needs a small background helper to control the MagSafe LED. Installing it asks for your admin password once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Install Helper…") {
                helper.install(initialConfig: settings.helperConfig)
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private var updatePrompt: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The background helper is older than the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Update Helper…") {
                helper.install(initialConfig: settings.helperConfig)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            SegmentedPicker(selection: $settings.mode, options: Self.modeOptions)

            Text(modeExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.mode == .auto {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Turn green at \(settings.threshold)%")
                        .font(.callout)
                    Slider(
                        value: Binding(
                            get: { Double(settings.threshold) },
                            set: { settings.threshold = Int($0.rounded()) }
                        ),
                        in: 10...100,
                        step: 5
                    )
                }
                chargeToFullButton
            }
        }
    }

    /// Plain-language description of whichever LED mode is selected.
    private var modeExplanation: String {
        switch settings.mode {
        case .auto:
            return "Shows green once the battery reaches the level you set below, and amber while it's still lower."
        case .off:
            return "Keeps the MagSafe light completely dark while the laptop is plugged in."
        case .system:
            return "Standard Mac behaviour — amber while charging, green only at a full 100%."
        }
    }

    @ViewBuilder
    private var chargeToFullButton: some View {
        if ChargeLimit.isSupported() {
            // Older firmware: MagHue lifts the limit itself via the helper.
            VStack(alignment: .leading, spacing: 3) {
                Button(settings.chargeToFull ? "Cancel Charge to Full" : "Charge to Full Once") {
                    settings.chargeToFull.toggle()
                }
                if settings.chargeToFull {
                    Text("The macOS charge limit is lifted until the battery hits 100%, then it comes back on its own. The LED still turns green at \(settings.threshold)%.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if SystemChargeToFull.isAvailableOnThisOS {
            // macOS 26.4+: press Apple's own "Charge to Full Now" for the user.
            VStack(alignment: .leading, spacing: 3) {
                Button("Charge to Full Now") { triggerSystemChargeToFull() }
                Text(systemChargeStatus ?? "Fills to 100% this once, then your limit returns on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func triggerSystemChargeToFull() {
        systemChargeStatus = "Asking macOS…"
        SystemChargeToFull.trigger { outcome in
            switch outcome {
            case .success:
                systemChargeStatus = "Told macOS to charge to 100%. It returns to your limit automatically."
            case .needsAccessibilityPermission:
                systemChargeStatus = "Turn on MagHue in System Settings → Privacy & Security → Accessibility, then try again."
            case .controlCenterUnavailable:
                systemChargeStatus = "Couldn't reach the system battery menu. Try again in a moment."
            case .buttonNotFound:
                systemChargeStatus = "No “Charge to Full Now” right now — this appears only while your Mac is holding at a charge limit on power."
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Notify when threshold is reached", isOn: $settings.notifyOnThreshold)
                .onChange(of: settings.notifyOnThreshold) { _, enabled in
                    if enabled { monitor.requestNotificationPermission() }
                }
            if let error = settings.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }

    // MARK: - Automation

    private var automation: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.schedules.isEmpty {
                Text("Schedule the light to change at set times — for example, off from sunset to sunrise every day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach($settings.schedules) { $schedule in
                    ScheduleEditor(schedule: $schedule) {
                        settings.deleteSchedule(id: schedule.id)
                    }
                }
            }

            Button {
                settings.addSchedule()
                ensureLocationIfNeeded()
            } label: {
                Label(settings.schedules.isEmpty ? "Add Your First Schedule" : "Add Schedule",
                      systemImage: "plus")
            }
            .buttonStyle(FilledButtonStyle())

            if settings.needsLocation {
                locationNote
            }
        }
        .onChange(of: settings.schedules) { _, _ in ensureLocationIfNeeded() }
    }

    @ViewBuilder
    private var locationNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(location.lastError ?? "Sunrise/sunset schedules need your location to know when the sun rises and sets.")
                .font(.caption)
                .foregroundStyle(location.lastError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Use My Location") { location.request() }
                .font(.caption)
        }
    }

    private func ensureLocationIfNeeded() {
        if settings.needsLocation,
           location.authorization == .authorized
            || location.authorization == .authorizedAlways {
            location.request()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if helper.isInstalled {
                Button {
                    helper.uninstall()
                } label: {
                    Label("Uninstall Helper", systemImage: "trash")
                }
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit MagHue", systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.caption)
    }

    // MARK: - Helpers

    /// A live preview of what the LED should look like right now.
    private var ledDot: some View {
        // The LED's "charging" color: amber, as Apple calls it.
        let ledAmber = Color(red: 1.0, green: 0.55, blue: 0.1)
        let color: Color
        switch settings.helperConfig.resolvedColor(for: monitor.state) {
        case .green: color = .green
        case .amber: color = ledAmber
        case .off: color = Color(nsColor: .darkGray)
        case .system:
            color = (monitor.state?.isCharged ?? false) ? .green
                : (monitor.state?.onACPower ?? false) ? ledAmber
                : Color(nsColor: .darkGray)
        }
        return Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .shadow(color: color.opacity(0.6), radius: 3)
    }

    private var batteryLine: String {
        guard let state = monitor.state else { return "No battery information" }
        var line = "\(state.percent)%"
        if state.isCharged {
            line += " • charged"
        } else if state.isCharging {
            line += " • charging"
        } else if state.onACPower {
            line += " • on power"
        } else {
            line += " • on battery"
        }
        if !helper.isInstalled {
            line += " • helper not installed"
        }
        return line
    }
}
