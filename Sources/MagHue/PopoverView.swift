import MagHueCore
import SwiftUI

/// How tall the scrolling content is and how far it has been scrolled.
private struct ScrollMetrics: Equatable {
    var content: CGFloat = 0
    var offset: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static let defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}

private struct ViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct PopoverView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var helper: HelperManager
    @ObservedObject var monitor: BatteryMonitor
    @ObservedObject var location: LocationProvider
    @State private var systemChargeStatus: String?
    @State private var tab: Tab
    /// Scroll geometry, used to hint that there's more content below.
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    enum Tab: Hashable { case light, automation }

    init(settings: Settings, helper: HelperManager, monitor: BatteryMonitor,
         location: LocationProvider, initialTab: Tab = .light) {
        self.settings = settings
        self.helper = helper
        self.monitor = monitor
        self.location = location
        _tab = State(initialValue: initialTab)
    }

    private static let scrollSpace = "popoverScroll"
    private static let bottomAnchor = "popoverBottom"

    /// True while part of the scrolling content is still below the fold.
    private var hasMoreBelow: Bool {
        contentHeight - scrollOffset - viewportHeight > 2
    }

    /// The popover grows to fit its content, so nothing normally needs
    /// scrolling. The only limit is the screen: with a long list of schedules
    /// the content area stops here and scrolls the rest.
    private var maxScrollHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, screen - 200)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header

            if helper.isInstalled {
                Picker("", selection: $tab) {
                    Text("Light").tag(Tab.light)
                    Text("Automation").tag(Tab.automation)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                scrollingBody

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

    /// The tab's content, in a scroll area that shows when there's more below:
    /// the last line fades out and a chevron appears that jumps to the end.
    private var scrollingBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    switch tab {
                    case .light:
                        controls
                        Divider()
                        options
                    case .automation:
                        automation
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(.horizontal, 1)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollMetricsKey.self,
                            value: ScrollMetrics(
                                content: geo.size.height,
                                offset: -geo.frame(in: .named(Self.scrollSpace)).minY
                            )
                        )
                    }
                )
            }
            .coordinateSpace(name: Self.scrollSpace)
            .scrollIndicators(.visible)
            .frame(maxHeight: maxScrollHeight)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ViewportHeightKey.self, value: geo.size.height)
                }
            )
            .mask(bottomFade)
            .overlay(alignment: .bottom) { moreBelowHint(proxy) }
            .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                contentHeight = metrics.content
                scrollOffset = metrics.offset
            }
            .onPreferenceChange(ViewportHeightKey.self) { viewportHeight = $0 }
        }
    }

    /// Softens the bottom edge while content continues past it.
    private var bottomFade: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(
                colors: [.black, .black.opacity(hasMoreBelow ? 0.05 : 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 18)
        }
        .animation(.easeInOut(duration: 0.15), value: hasMoreBelow)
    }

    private func moreBelowHint(_ proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(.quaternary))
        }
        .buttonStyle(.plain)
        .help("There's more below — click to scroll down")
        .opacity(hasMoreBelow ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hasMoreBelow)
    }

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
        }
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
            Picker("LED", selection: $settings.mode) {
                Text("Custom").tag(LEDMode.auto)
                Text("Off").tag(LEDMode.off)
                Text("System").tag(LEDMode.system)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

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
            Toggle("Show percentage in menu bar", isOn: $settings.showPercentInMenuBar)
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
                Label("Add Schedule", systemImage: "plus")
            }

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
