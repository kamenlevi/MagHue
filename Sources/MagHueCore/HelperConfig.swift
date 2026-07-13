import Foundation

/// Shared constants and the on-disk config the app writes and the helper reads.
public enum MagHue {
    public static let helperLabel = "com.kamenlevi.maghue.helper"
    public static let helperBinaryPath = "/Library/PrivilegedHelperTools/\(helperLabel)"
    public static let helperPlistPath = "/Library/LaunchDaemons/\(helperLabel).plist"
    public static let configDirectory = "/Library/Application Support/MagHue"
    public static let configPath = "\(configDirectory)/config.json"
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

    public init(mode: LEDMode = .auto, threshold: Int = 80) {
        self.mode = mode
        self.threshold = min(max(threshold, 10), 100)
    }

    public static func load() -> HelperConfig {
        guard let data = FileManager.default.contents(atPath: MagHue.configPath),
              let config = try? JSONDecoder().decode(HelperConfig.self, from: data)
        else { return HelperConfig() }
        return HelperConfig(mode: config.mode, threshold: config.threshold)
    }

    public func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: MagHue.configPath), options: .atomic)
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
