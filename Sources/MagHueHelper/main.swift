import Foundation
import IOKit.ps
import MagHueCore
import os

/// maghue-helper — root launchd daemon.
///
/// Watches the battery and the config file, and keeps the MagSafe LED in the
/// color MagHue wants. Hands the LED back to macOS (ACLC = 0) on shutdown.
///
/// Flags:
///   --reset   write ACLC = 0 and exit (used by the uninstaller)
///   --probe   print whether this Mac exposes the ACLC key, and battery state

let log = Logger(subsystem: "com.kamenlevi.maghue", category: "helper")

if CommandLine.arguments.contains("--reset") {
    do {
        try MagSafeLED.set(.system)
        print("MagSafe LED handed back to macOS")
        exit(0)
    } catch {
        print("reset failed: \(error)")
        exit(1)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--read"),
   CommandLine.arguments.count > index + 1 {
    let key = CommandLine.arguments[index + 1]
    do {
        let bytes = try SMC.readBytes(key)
        print(key, bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
    } catch {
        print("\(key) read failed: \(error)")
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--keys") {
    do {
        for key in try SMC.allKeys().sorted() {
            let info = (try? SMC.keyInfo(key)).map { "size=\($0.size) type=\($0.type)" } ?? ""
            print(key, info)
        }
    } catch {
        print("key enumeration failed: \(error)")
        exit(1)
    }
    exit(0)
}

if CommandLine.arguments.contains("--probe") {
    do {
        let info = try SMC.keyInfo(MagSafeLED.key)
        print("ACLC present: size=\(info.size) type=\(info.type)")
    } catch {
        print("ACLC probe failed: \(error)")
    }
    if ChargeLimit.isSupported(), let limit = try? ChargeLimit.read() {
        print("charge limit: \(limit.active ? "active \(limit.lower)-\(limit.upper)%" : "off (charges to 100%)")")
    } else {
        print("charge limit: keys unavailable — Charge to Full is disabled on this Mac")
    }
    if let battery = Battery.read() {
        print("battery: \(battery.percent)% onAC=\(battery.onACPower) " +
              "charging=\(battery.isCharging) charged=\(battery.isCharged)")
        print("desired LED for current config: \(HelperConfig.load().desiredColor(for: battery))")
    } else {
        print("no internal battery found")
    }
    exit(0)
}

final class Daemon {
    private var config = HelperConfig.load()
    private var lastWritten: MagSafeLED.Color?
    private var wasOnAC = false
    private var configWatcher: DispatchSourceFileSystemObject?

    // Charge to Full: whether we lifted the macOS charge limit and therefore
    // owe a restore once the battery is full, plus the bounds to restore.
    // Persisted so a helper restart mid-charge still restores the limit.
    private var chargeToFullActive = false
    private var restoreLimitWhenDone = false
    private var savedLower = 0
    private var savedUpper = 100

    func run() {
        log.info("maghue-helper starting; mode=\(self.config.mode.rawValue, privacy: .public) threshold=\(self.config.threshold)")
        loadChargeToFullState()

        // React the moment power state changes (plug/unplug, percent ticks).
        let callback: IOPowerSourceCallbackType = { context in
            let daemon = Unmanaged<Daemon>.fromOpaque(context!).takeUnretainedValue()
            daemon.evaluate()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        watchConfigDirectory()
        installSignalHandlers()

        // Safety net in case an event is missed.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .default)

        evaluate()
        RunLoop.main.run()
    }

    private func watchConfigDirectory() {
        // Watch the directory, not the file: the app replaces the file atomically.
        let fd = open(MagHue.configDirectory, O_EVTONLY)
        guard fd >= 0 else {
            log.error("cannot watch config directory")
            return
        }
        let watcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        watcher.setEventHandler { [weak self] in self?.reloadConfig() }
        watcher.setCancelHandler { close(fd) }
        watcher.resume()
        configWatcher = watcher
    }

    private func reloadConfig() {
        let fresh = HelperConfig.load()
        guard fresh != config else { return }
        config = fresh
        log.info("config changed; mode=\(self.config.mode.rawValue, privacy: .public) threshold=\(self.config.threshold)")
        evaluate()
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                log.info("shutting down; handing LED back to macOS")
                // Never leave the charge limit lifted behind our back. The
                // state file stays, so a restart resumes the charge-to-full.
                if let self, self.chargeToFullActive, self.restoreLimitWhenDone {
                    try? ChargeLimit.enable(lower: self.savedLower, upper: self.savedUpper)
                }
                try? MagSafeLED.set(.system)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    // MARK: - Charge to Full

    private func loadChargeToFullState() {
        guard let data = FileManager.default.contents(atPath: MagHue.helperStatePath),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        restoreLimitWhenDone = state["restoreLimit"] as? Bool ?? false
        savedLower = state["lower"] as? Int ?? 0
        savedUpper = state["upper"] as? Int ?? 100
        chargeToFullActive = config.chargeToFull
        if !chargeToFullActive {
            // We died between restoring and clearing state; finish the job.
            finishChargeToFull(reason: "stale state")
        }
    }

    private func saveChargeToFullState() {
        let payload: [String: Any] = ["restoreLimit": restoreLimitWhenDone,
                                      "lower": savedLower, "upper": savedUpper]
        let data = try? JSONSerialization.data(withJSONObject: payload)
        try? data?.write(to: URL(fileURLWithPath: MagHue.helperStatePath))
    }

    private func evaluateChargeToFull(battery: BatteryState?) {
        if config.chargeToFull {
            guard ChargeLimit.isSupported() else {
                // No safe way to lift the limit on this Mac's firmware; don't
                // pretend. Clear the flag so the UI reflects reality.
                log.error("charge to full requested but charge-limit keys are unavailable")
                chargeToFullActive = false
                clearChargeToFullFlag()
                return
            }
            if !chargeToFullActive {
                let limit = (try? ChargeLimit.read()) ?? ChargeLimit.State(active: false, lower: 0, upper: 100)
                restoreLimitWhenDone = limit.active
                savedLower = limit.lower
                savedUpper = limit.upper
                chargeToFullActive = true
                saveChargeToFullState()
                if limit.active {
                    do {
                        try ChargeLimit.disable()
                        log.info("charge to full: lifted charge limit (was \(limit.lower)-\(limit.upper)%)")
                    } catch {
                        log.error("charge to full: could not lift limit: \(String(describing: error), privacy: .public)")
                    }
                } else {
                    log.info("charge to full: no charge limit active, nothing to lift")
                }
            } else if restoreLimitWhenDone {
                // macOS occasionally reasserts the limit; keep it lifted.
                if (try? ChargeLimit.read())?.active == true {
                    try? ChargeLimit.disable()
                    log.info("charge to full: re-lifted the charge limit")
                }
            }
            if let battery, battery.percent >= 100 || battery.isCharged {
                finishChargeToFull(reason: "battery full")
            }
        } else if chargeToFullActive {
            finishChargeToFull(reason: "cancelled")
        }
    }

    private func finishChargeToFull(reason: String) {
        if restoreLimitWhenDone {
            do {
                try ChargeLimit.enable(lower: savedLower, upper: savedUpper)
                log.info("charge to full done (\(reason, privacy: .public)); restored \(self.savedLower)-\(self.savedUpper)% limit")
            } catch {
                log.error("charge to full: could not restore limit: \(String(describing: error), privacy: .public)")
            }
        } else {
            log.info("charge to full done (\(reason, privacy: .public))")
        }
        chargeToFullActive = false
        restoreLimitWhenDone = false
        try? FileManager.default.removeItem(atPath: MagHue.helperStatePath)
        clearChargeToFullFlag()
    }

    private func clearChargeToFullFlag() {
        guard config.chargeToFull else { return }
        var cleared = config
        cleared.chargeToFull = false
        try? cleared.saveInPlace()
        config = cleared
    }

    // MARK: - LED

    func evaluate() {
        let battery = Battery.read()
        evaluateChargeToFull(battery: battery)
        let desired = config.desiredColor(for: battery)
        let onAC = battery?.onACPower ?? false

        // Re-assert on every re-plug even if the value is unchanged: a fresh
        // connection starts under system control.
        let force = onAC && !wasOnAC
        wasOnAC = onAC
        guard desired != lastWritten || force else { return }

        do {
            try MagSafeLED.set(desired)
            lastWritten = desired
            log.info("LED -> \(String(describing: desired), privacy: .public) (battery \(battery?.percent ?? -1)%)")
        } catch {
            log.error("SMC write failed: \(String(describing: error), privacy: .public)")
        }
    }
}

Daemon().run()
