import Combine
import Foundation
import MagHueCore

/// Installs, removes, and feeds config to the privileged helper daemon.
final class HelperManager: ObservableObject {
    @Published private(set) var isInstalled: Bool = false
    @Published var lastError: String?

    init() {
        refresh()
    }

    func refresh() {
        let fm = FileManager.default
        isInstalled = fm.fileExists(atPath: MagHue.helperPlistPath)
            && fm.fileExists(atPath: MagHue.helperBinaryPath)
    }

    /// Writes the config file the helper watches. The installer chowns the
    /// config directory to the installing user, so no privileges are needed.
    func write(config: HelperConfig) {
        guard isInstalled else { return }
        do {
            try config.save()
            lastError = nil
        } catch {
            lastError = "Could not update helper config: \(error.localizedDescription)"
        }
    }

    func install(initialConfig: HelperConfig) {
        runPrivilegedScript(named: "install-helper.sh") { [weak self] success in
            guard let self else { return }
            self.refresh()
            if success {
                self.write(config: initialConfig)
            }
        }
    }

    func uninstall() {
        runPrivilegedScript(named: "uninstall-helper.sh") { [weak self] _ in
            self?.refresh()
        }
    }

    /// Runs a bundled script as root via the system admin-password prompt.
    private func runPrivilegedScript(named scriptName: String,
                                     completion: @escaping (Bool) -> Void) {
        guard let scriptPath = Bundle.main.path(forResource: scriptName, ofType: nil),
              let resourcePath = Bundle.main.resourcePath else {
            lastError = "Helper resources missing; run the built MagHue.app bundle."
            completion(false)
            return
        }
        let userName = NSUserName()
        let command = [scriptPath, resourcePath, userName]
            .map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: " ")
        let escaped = "/bin/bash \(command)"
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            DispatchQueue.main.async {
                if result == nil {
                    let message = errorInfo?[NSAppleScript.errorMessage] as? String
                    // -128 is the user cancelling the password prompt; stay quiet.
                    let code = errorInfo?[NSAppleScript.errorNumber] as? Int
                    self.lastError = code == -128 ? nil : (message ?? "Helper script failed.")
                    completion(false)
                } else {
                    self.lastError = nil
                    completion(true)
                }
            }
        }
    }
}
