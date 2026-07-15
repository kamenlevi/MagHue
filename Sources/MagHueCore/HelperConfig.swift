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
    public static let helperStatePath = "\(configDirectory)/helper-state.json"
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
        case .automatic: return "Automatic"
        }
    }
}

/// A point in the day a schedule starts or ends: a fixed clock time, or a
/// solar event resolved from the user's location.
public struct TimeAnchor: Codable, Equatable {
    public enum Kind: String, Codable { case clock, sunset, sunrise }
    public var kind: Kind
    public var hour: Int
    public var minute: Int

    public init(kind: Kind = .clock, hour: Int = 22, minute: Int = 0) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
    }

    public static let sunset = TimeAnchor(kind: .sunset, hour: 0, minute: 0)
    public static let sunrise = TimeAnchor(kind: .sunrise, hour: 0, minute: 0)

    /// Minutes from local midnight for this anchor on `date`, or nil if a
    /// solar anchor can't be resolved (no location / polar day or night).
    public func minutesFromMidnight(on date: Date, calendar: Calendar,
                                    latitude: Double?, longitude: Double?) -> Int? {
        switch kind {
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

    public init(mode: LEDMode = .auto, threshold: Int = 80, chargeToFull: Bool = false,
                schedules: [Schedule] = [], latitude: Double? = nil, longitude: Double? = nil) {
        self.mode = mode
        self.threshold = min(max(threshold, 10), 100)
        self.chargeToFull = chargeToFull
        self.schedules = schedules
        self.latitude = latitude
        self.longitude = longitude
    }

    enum CodingKeys: String, CodingKey {
        case mode, threshold, chargeToFull, schedules, latitude, longitude
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
        self.init(mode: mode, threshold: threshold, chargeToFull: chargeToFull,
                  schedules: schedules, latitude: latitude, longitude: longitude)
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

    /// The first enabled schedule active at `date`, if any.
    public func activeSchedule(at date: Date, calendar: Calendar = .current) -> Schedule? {
        let nowMinutes = { () -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }()
        let today = calendar.component(.weekday, from: date)
        let yesterday = calendar.component(
            .weekday, from: calendar.date(byAdding: .day, value: -1, to: date) ?? date)

        for schedule in schedules where schedule.enabled && !schedule.days.isEmpty {
            guard let start = schedule.start.minutesFromMidnight(
                    on: date, calendar: calendar, latitude: latitude, longitude: longitude),
                  let end = schedule.end.minutesFromMidnight(
                    on: date, calendar: calendar, latitude: latitude, longitude: longitude),
                  start != end
            else { continue }

            if start < end {
                if schedule.days.contains(today), nowMinutes >= start, nowMinutes < end {
                    return schedule
                }
            } else {
                // Window wraps past midnight.
                if schedule.days.contains(today), nowMinutes >= start { return schedule }
                if schedule.days.contains(yesterday), nowMinutes < end { return schedule }
            }
        }
        return nil
    }

    /// The LED color this config wants right now, honoring active schedules.
    public func resolvedColor(for battery: BatteryState?,
                              at date: Date = Date(),
                              calendar: Calendar = .current) -> MagSafeLED.Color {
        if let schedule = activeSchedule(at: date, calendar: calendar) {
            return color(for: schedule.action, battery: battery)
        }
        return baseColor(for: battery)
    }

    /// Retained for callers that only want the base mode's color.
    public func desiredColor(for battery: BatteryState?) -> MagSafeLED.Color {
        baseColor(for: battery)
    }
}
