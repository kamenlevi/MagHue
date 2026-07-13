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

if CommandLine.arguments.contains("--probe") {
    do {
        let info = try SMC.keyInfo(MagSafeLED.key)
        print("ACLC present: size=\(info.size) type=\(info.type)")
    } catch {
        print("ACLC probe failed: \(error)")
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

    func run() {
        log.info("maghue-helper starting; mode=\(self.config.mode.rawValue, privacy: .public) threshold=\(self.config.threshold)")

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
            source.setEventHandler {
                log.info("shutting down; handing LED back to macOS")
                try? MagSafeLED.set(.system)
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
    private var signalSources: [DispatchSourceSignal] = []

    func evaluate() {
        let battery = Battery.read()
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
