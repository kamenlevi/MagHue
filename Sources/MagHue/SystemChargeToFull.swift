import AppKit
import ApplicationServices

/// Best-effort "Charge to Full Now" by driving macOS's own Control Center
/// battery menu through the Accessibility API — instead of reimplementing the
/// charge limit ourselves. This is what runs on macOS 26.4+ Macs where Apple's
/// native Charge Limit is in charge and the SMC firmware keys aren't exposed.
///
/// It is inherently fragile: it depends on the Accessibility permission, on the
/// English menu label "Charge to Full Now", and on Control Center's internal
/// layout. When it can't find the button it writes an AX dump to
/// /tmp/maghue-ax-dump.txt so the element lookup can be corrected.
enum SystemChargeToFull {
    enum Outcome {
        case success
        case needsAccessibilityPermission
        case controlCenterUnavailable
        case buttonNotFound
    }

    /// Whether Apple's native Charge Limit (and its "Charge to Full Now" menu)
    /// exists on this OS. It arrived in macOS 26.4.
    static var isAvailableOnThisOS: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 0))
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Apple's own localization table for the Control Center battery menu.
    /// Reading the labels from here means the lookup matches the button in
    /// whatever language macOS is running — the strings are, by definition,
    /// exactly the ones on screen. The English literals below are only the
    /// fallback for the day Apple moves or renames the file.
    private static let appleBatteryLoctable =
        "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/Battery.loctable"

    /// Every localization of `key` in Apple's table (lowercased), plus the
    /// fallbacks. All 41 languages go into the needle list rather than just
    /// the current one, so nothing depends on guessing which locale Control
    /// Center is actually drawing in.
    private static func appleLocalizations(of key: String, fallback: [String]) -> [String] {
        guard let data = FileManager.default.contents(atPath: appleBatteryLoctable),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: [String: Any]]
        else { return fallback }
        var needles = Set(fallback)
        for locale in table.values {
            if let value = locale[key] as? String {
                needles.insert(value.lowercased())
            }
        }
        return Array(needles)
    }

    private static let chargeLabels = appleLocalizations(
        of: "Charge to Full Now", fallback: ["charge to full now", "charge to full"])
    private static let batteryHints = appleLocalizations(
        of: "Battery", fallback: ["battery"])

    static func trigger(completion: @escaping (Outcome) -> Void) {
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            completion(.needsAccessibilityPermission)
            return
        }
        guard let cc = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.controlcenter"
        }) else {
            completion(.controlCenterUnavailable)
            return
        }

        let app = AXUIElementCreateApplication(cc.processIdentifier)
        guard let batteryItem = findBatteryMenuBarItem(app) else {
            dump(app, reason: "battery menu bar item not found")
            completion(.buttonNotFound)
            return
        }

        // Open the battery menu, then look for the button once it's on screen.
        AXUIElementPerformAction(batteryItem, kAXPressAction as CFString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let button = findElement(app, matchingAny: chargeLabels, maxDepth: 12) {
                AXUIElementPerformAction(button, kAXPressAction as CFString)
                completion(.success)
            } else {
                dump(app, reason: "‘Charge to Full Now’ not found in open menu")
                // Close the menu we opened so we don't leave it hanging.
                AXUIElementPerformAction(batteryItem, kAXPressAction as CFString)
                completion(.buttonNotFound)
            }
        }
    }

    // MARK: - AX helpers

    private static func copyValue(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
            ? value : nil
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (copyValue(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func label(_ element: AXUIElement) -> String {
        let parts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { copyValue(element, $0 as String) as? String }
        return parts.joined(separator: " ").lowercased()
    }

    private static func findBatteryMenuBarItem(_ app: AXUIElement) -> AXUIElement? {
        for barAttribute in ["AXExtrasMenuBar", kAXMenuBarAttribute as String] {
            guard let bar = copyValue(app, barAttribute) else { continue }
            let barElement = bar as! AXUIElement
            for item in children(barElement) where batteryHints.contains(where: label(item).contains) {
                return item
            }
        }
        return nil
    }

    private static func findElement(_ element: AXUIElement,
                                    matchingAny needles: [String],
                                    maxDepth: Int) -> AXUIElement? {
        // Search the app's open windows plus any menus.
        var roots = children(element)
        if let windows = copyValue(element, kAXWindowsAttribute as String) as? [AXUIElement] {
            roots += windows
        }
        for root in roots {
            if let hit = search(root, needles: needles, depth: maxDepth) { return hit }
        }
        return nil
    }

    private static func search(_ element: AXUIElement, needles: [String], depth: Int) -> AXUIElement? {
        if depth < 0 { return nil }
        let text = label(element)
        if needles.contains(where: text.contains) { return element }
        for child in children(element) {
            if let hit = search(child, needles: needles, depth: depth - 1) { return hit }
        }
        return nil
    }

    private static func dump(_ app: AXUIElement, reason: String) {
        var lines = ["MagHue AX dump — \(reason)", ""]
        func walk(_ element: AXUIElement, indent: Int, depth: Int) {
            guard depth >= 0 else { return }
            let role = (copyValue(element, kAXRoleAttribute as String) as? String) ?? "?"
            lines.append(String(repeating: "  ", count: indent) + "\(role): \(label(element))")
            for child in children(element) { walk(child, indent: indent + 1, depth: depth - 1) }
        }
        walk(app, indent: 0, depth: 8)
        try? lines.joined(separator: "\n")
            .write(toFile: "/tmp/maghue-ax-dump.txt", atomically: true, encoding: .utf8)
    }
}
