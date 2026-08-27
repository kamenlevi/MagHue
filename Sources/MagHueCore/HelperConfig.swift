import Foundation

/// Shared constants and the on-disk config the app writes and the helper reads.
public enum MagHue {
    public static let helperLabel = "com.kamenlevi.maghue.helper"
    public static let helperBinaryPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    public static let helperPlistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
    public static let configDirectory = "/Library/Application Support/MagHue"
    public static let configPath = "\(configDirectory)/config.json"
    /// Root-owned scratch state the helper keeps across restarts
    /// (currently: whether Charge to Full must restore the charge limit).
    /// Lives outside the user-owned config directory: whoever owns a file's
    /// parent can replace the file, and this one feeds root SMC writes.
    public static let helperStateDirectory = "/var/db/maghue"
    public static let helperStatePath = "\(helperStateDirectory)/helper-state.json"
    /// Where the state file used to live, inside the user-owned config
    /// directory. Untrusted; deleted on helper start, never read.
    public static let legacyHelperStatePath = "\(configDirectory)/helper-state.json"
}

public enum LEDMode: String, Codable, CaseIterable {
    /// Green at/above the threshold while on power, amber below it.
    case auto
    /// LED always off.
    case off
    /// Hand the LED back to macOS (stock behavior).
    case system
}

/// What a scheduled rule makes the LED do while it's active.
public enum ScheduleAction: String, Codable, CaseIterable {
    case off        // dark
    case green      // force green
    case amber      // force amber
    case system     // hand back to macOS
    case automatic  // normal threshold behavior

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .green: return "Green"
        case .amber: return "Amber"
        case .system: return "System"
        case .automatic: return "Custom"
        }
    }
}

/// A point in the day a schedule starts or ends: a fixed clock time, or a
/// solar event resolved from the user's location.
public struct TimeAnchor: Codable, Equatable {
    /// What a rule's start or end is pinned to. `percent` makes the rule
    /// depend on the battery rather than the clock, so "off once it reaches
    /// 80%" is a rule like any other.
    public enum Kind: String, Codable { case clock, sunset, sunrise, percent }
    public var kind: Kind
    public var hour: Int
    public var minute: Int
    /// Battery percentage, used only when `kind` is `.percent`.
    public var percent: Int

    public init(kind: Kind = .clock, hour: Int = 22, minute: Int = 0,
                percent: Int = 80) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
        self.percent = min(max(percent, 0), 100)
    }

    public static let sunset = TimeAnchor(kind: .sunset, hour: 0, minute: 0)
    public static let sunrise = TimeAnchor(kind: .sunrise, hour: 0, minute: 0)
    public static func battery(_ percent: Int) -> TimeAnchor {
        TimeAnchor(kind: .percent, hour: 0, minute: 0, percent: percent)
    }

    /// True when this anchor is about the clock rather than the battery.
    public var isTimeBased: Bool { kind != .percent }

    // Config files written before battery anchors existed have no `percent`.
    enum CodingKeys: String, CodingKey { case kind, hour, minute, percent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .clock,
                  hour: try c.decodeIfPresent(Int.self, forKey: .hour) ?? 22,
                  minute: try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0,
                  percent: try c.decodeIfPresent(Int.self, forKey: .percent) ?? 80)
    }

    /// Minutes from local midnight for this anchor on `date`, or nil if it
    /// isn't a clock anchor at all, or a solar one can't be resolved (no
    /// location / polar day or night).
    public func minutesFromMidnight(on date: Date, calendar: Calendar,
                                    latitude: Double?, longitude: Double?) -> Int? {
        switch kind {
        case .percent:
            return nil
        case .clock:
            return hour * 60 + minute
        case .sunrise, .sunset:
            guard let latitude, let longitude,
                  let events = SolarTimes.events(latitude: latitude, longitude: longitude,
                                                 on: date, calendar: calendar) else { return nil }
            let event = (kind == .sunrise) ? events.sunrise : events.sunset
            let comps = calendar.dateComponents([.hour, .minute], from: event)
            return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        }
    }
}

/// One time-based rule: on the chosen weekdays, between `start` and `end`,
/// force the LED to `action`. A window whose end is earlier than its start
/// wraps past midnight.
public struct Schedule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var enabled: Bool
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
    public var days: Set<Int>
    public var start: TimeAnchor
    public var end: TimeAnchor
    public var action: ScheduleAction

    public init(id: UUID = UUID(), enabled: Bool = true,
                days: Set<Int> = Set(1...7),
                start: TimeAnchor = .sunset, end: TimeAnchor = .sunrise,
                action: ScheduleAction = .off) {
        self.id = id
        self.enabled = enabled
        self.days = days
        self.start = start
        self.end = end
        self.action = action
    }
}

public struct HelperConfig: Codable, Equatable {
    public var mode: LEDMode
    /// Battery percentage at which the LED turns green in `auto` mode.
    public var threshold: Int
    /// One-shot: lift the macOS charge limit until the battery hits 100%.
    public var chargeToFull: Bool
    /// Time-based rules that override the base mode while active.
    public var schedules: [Schedule]
    /// Cached location for resolving sunrise/sunset anchors (set by the app).
    public var latitude: Double?
    public var longitude: Double?
    /// Seconds to show the real charging colour after the cable is connected,
    /// before the resolved mode takes over. 0 disables the grace window, which
    /// keeps the previous behaviour for configs written before this key existed.
    public var graceSeconds: Int

    public init(mode: LEDMode = .auto, threshold: Int = 80, chargeToFull: Bool = false,
                schedules: [Schedule] = [], latitude: Double? = nil, longitude: Double? = nil,
                graceSeconds: Int = 0) {
        self.mode = mode
        self.threshold = min(max(threshold, 10), 100)
        self.chargeToFull = chargeToFull
        self.schedules = schedules
        self.latitude = latitude
        self.longitude = longitude
        self.graceSeconds = min(max(graceSeconds, 0), 600)
    }

    enum CodingKeys: String, CodingKey {
        case mode, threshold, chargeToFull, schedules, latitude, longitude, graceSeconds
    }

    // Tolerate config files written by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(LEDMode.self, forKey: .mode) ?? .auto
        let threshold = try container.decodeIfPresent(Int.self, forKey: .threshold) ?? 80
        let chargeToFull = try container.decodeIfPresent(Bool.self, forKey: .chargeToFull) ?? false
        let schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        let latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        let longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        let graceSeconds = try container.decodeIfPresent(Int.self, forKey: .graceSeconds) ?? 0
        self.init(mode: mode, threshold: threshold, chargeToFull: chargeToFull,
                  schedules: schedules, latitude: latitude, longitude: longitude,
                  graceSeconds: graceSeconds)
    }

    public static func load() -> HelperConfig {
        guard let data = FileManager.default.contents(atPath: MagHue.configPath),
              let config = try? JSONDecoder().decode(HelperConfig.self, from: data)
        else { return HelperConfig() }
        return config
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: MagHue.configPath), options: .atomic)
    }

    /// Rewrites the config without replacing the file, so the helper (root)
    /// can update it while the file stays owned — and writable — by the user.
    public func saveInPlace() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        if let handle = FileHandle(forWritingAtPath: MagHue.configPath) {
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: URL(fileURLWithPath: MagHue.configPath))
        }
    }

    /// The LED color the base mode (ignoring schedules) wants.
    public func baseColor(for battery: BatteryState?) -> MagSafeLED.Color {
        switch mode {
        case .system:
            return .system
        case .off:
            return .off
        case .auto:
            return autoColor(for: battery)
        }
    }

    private func autoColor(for battery: BatteryState?) -> MagSafeLED.Color {
        guard let battery, battery.onACPower else { return .system }
        return battery.percent >= threshold ? .green : .amber
    }

    private func color(for action: ScheduleAction, battery: BatteryState?) -> MagSafeLED.Color {
        switch action {
        case .off: return .off
        case .green: return .green
        case .amber: return .amber
        case .system: return .system
        case .automatic: return autoColor(for: battery)
        }
    }

    /// The first enabled schedule active right now, if any.
    ///
    /// A rule's two anchors can each be a clock time (including sunset and
    /// sunrise) or a battery percentage, and they combine like this:
    ///
    /// - Two clock anchors: the usual time window, wrapping past midnight.
    /// - Two battery anchors: active while the battery sits between them,
    ///   whichever order they were entered in.
    /// - One of each: each anchor becomes a single bound and both must hold,
    ///   so "from 80% to 22:00" means at or above 80% and before 22:00.
    ///
    /// The weekday set applies either way.
    public func activeSchedule(at date: Date = Date(),
                               calendar: Calendar = .current,
                               battery: BatteryState? = nil) -> Schedule? {
        let nowMinutes = { () -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }()
        let today = calendar.component(.weekday, from: date)
        let yesterday = calendar.component(
            .weekday, from: calendar.date(byAdding: .day, value: -1, to: date) ?? date)

        func minutes(_ anchor: TimeAnchor) -> Int? {
            anchor.minutesFromMidnight(on: date, calendar: calendar,
                                       latitude: latitude, longitude: longitude)
        }

        for schedule in schedules where schedule.enabled && !schedule.days.isEmpty {
            guard schedule.days.contains(today) || schedule.days.contains(yesterday) else {
                continue
            }
            let startsOnTime = schedule.start.isTimeBased
            let endsOnTime = schedule.end.isTimeBased

            switch (startsOnTime, endsOnTime) {
            case (true, true):
                guard let start = minutes(schedule.start), let end = minutes(schedule.end),
                      start != end else { continue }
                if start < end {
                    if schedule.days.contains(today), nowMinutes >= start, nowMinutes < end {
                        return schedule
                    }
                } else {
                    // Window wraps past midnight.
                    if schedule.days.contains(today), nowMinutes >= start { return schedule }
                    if schedule.days.contains(yesterday), nowMinutes < end { return schedule }
                }

            case (false, false):
                // A battery range. Entering it backwards is a slip, not a
                // wrap: a battery can't run past 100% into 0% the way a clock
                // runs past midnight.
                guard schedule.days.contains(today), let percent = battery?.percent else { continue }
                let low = min(schedule.start.percent, schedule.end.percent)
                let high = max(schedule.start.percent, schedule.end.percent)
                if percent >= low, percent <= high { return schedule }

            default:
                // Mixed: each anchor is one bound and both have to hold.
                guard schedule.days.contains(today) else { continue }
                let startHolds: Bool
                if startsOnTime {
                    guard let start = minutes(schedule.start) else { continue }
                    startHolds = nowMinutes >= start
                } else {
                    guard let percent = battery?.percent else { continue }
                    startHolds = percent >= schedule.start.percent
                }

                let endHolds: Bool
                if endsOnTime {
                    guard let end = minutes(schedule.end) else { continue }
                    endHolds = nowMinutes < end
                } else {
                    guard let percent = battery?.percent else { continue }
                    endHolds = percent <= schedule.end.percent
                }

                if startHolds, endHolds { return schedule }
            }
        }
        return nil
    }

    /// The LED color this config wants right now, honoring active schedules.
    public func resolvedColor(for battery: BatteryState?,
                              at date: Date = Date(),
                              calendar: Calendar = .current) -> MagSafeLED.Color {
        if let schedule = activeSchedule(at: date, calendar: calendar, battery: battery) {
            return color(for: schedule.action, battery: battery)
        }
        return baseColor(for: battery)
    }

    /// Retained for callers that only want the base mode's color.
    public func desiredColor(for battery: BatteryState?) -> MagSafeLED.Color {
        baseColor(for: battery)
    }
}
