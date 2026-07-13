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

public struct HelperConfig: Codable, Equatable {
    public var mode: LEDMode
    /// Battery percentage at which the LED turns green in `auto` mode.
    public var threshold: Int
    /// One-shot: lift the macOS charge limit until the battery hits 100%.
    public var chargeToFull: Bool

    public init(mode: LEDMode = .auto, threshold: Int = 80, chargeToFull: Bool = false) {
        self.mode = mode
        self.threshold = min(max(threshold, 10), 100)
        self.chargeToFull = chargeToFull
    }

    enum CodingKeys: String, CodingKey {
        case mode, threshold, chargeToFull
    }

    // Tolerate config files written by older versions that lack newer keys.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(LEDMode.self, forKey: .mode) ?? .auto
        let threshold = try container.decodeIfPresent(Int.self, forKey: .threshold) ?? 80
        let chargeToFull = try container.decodeIfPresent(Bool.self, forKey: .chargeToFull) ?? false
        self.init(mode: mode, threshold: threshold, chargeToFull: chargeToFull)
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

    /// The LED color this config wants for a given battery state.
    public func desiredColor(for battery: BatteryState?) -> MagSafeLED.Color {
        switch mode {
        case .system:
            return .system
        case .off:
            return .off
        case .auto:
            guard let battery, battery.onACPower else { return .system }
            return battery.percent >= threshold ? .green : .amber
        }
    }
}
