import Foundation
import IOKit.ps

public struct BatteryState: Equatable {
    public var percent: Int
    public var onACPower: Bool
    public var isCharging: Bool
    public var isCharged: Bool

    public init(percent: Int, onACPower: Bool, isCharging: Bool, isCharged: Bool) {
        self.percent = percent
        self.onACPower = onACPower
        self.isCharging = isCharging
        self.isCharged = isCharged
    }
}

public enum Battery {
    /// Reads the internal battery's state, or nil on desktops / read failure.
    public static func read() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let percent = description[kIOPSCurrentCapacityKey] as? Int
            else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            return BatteryState(
                percent: percent,
                onACPower: state == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isCharged: description[kIOPSIsChargedKey] as? Bool ?? false
            )
        }
        return nil
    }
}
