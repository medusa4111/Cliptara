import Foundation
import ServiceManagement

enum LaunchAtLoginError: LocalizedError {
    case executableNotFound
    case writeFailed
    case removeFailed
    case registerFailed(String)
    case unregisterFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return Localizer.text(
                "Не удалось определить исполняемый файл приложения.",
                "Could not resolve the app executable path."
            )
        case .writeFailed:
            return Localizer.text(
                "Не удалось включить автозапуск.",
                "Could not enable launch at login."
            )
        case .removeFailed:
            return Localizer.text(
                "Не удалось выключить автозапуск.",
                "Could not disable launch at login."
            )
        case .registerFailed(let details):
            return Localizer.text(
                "Не удалось включить автозапуск.\n\(details)",
                "Could not enable launch at login.\n\(details)"
            )
        case .unregisterFailed(let details):
            return Localizer.text(
                "Не удалось выключить автозапуск.\n\(details)",
                "Could not disable launch at login.\n\(details)"
            )
        }
    }
}

final class LaunchAtLoginManager {
    private let fileManager = FileManager.default

    func isEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                return true
            case .notFound, .notRegistered:
                return false
            @unknown default:
                return false
            }
        }
        return fileManager.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    if service.status != .enabled && service.status != .requiresApproval {
                        try service.register()
                    }
                } else {
                    if service.status != .notRegistered {
                        try service.unregister()
                    }
                }
            } catch {
                if enabled {
                    throw LaunchAtLoginError.registerFailed(error.localizedDescription)
                } else {
                    throw LaunchAtLoginError.unregisterFailed(error.localizedDescription)
                }
            }

            // Remove old LaunchAgent-based setup from previous versions to avoid duplicate autostart.
            try? removeLaunchAgent()
            return
        }

        if enabled {
            try installLaunchAgent()
            return
        }
        try removeLaunchAgent()
    }

    private var launchAgentURL: URL {
        let launchAgentsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        return launchAgentsDirectory
            .appendingPathComponent("\(agentLabel).plist", isDirectory: false)
    }

    private var agentLabel: String {
        "\(Bundle.main.bundleIdentifier ?? "com.maksim.cliptara").autostart"
    }

    private func installLaunchAgent() throws {
        guard let executablePath = resolveExecutablePath() else {
            throw LaunchAtLoginError.executableNotFound
        }

        let launchAgentsDirectory = launchAgentURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
        } catch {
            throw LaunchAtLoginError.writeFailed
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": ["Aqua"]
        ]

        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: launchAgentURL, options: .atomic)
        } catch {
            throw LaunchAtLoginError.writeFailed
        }
    }

    private func removeLaunchAgent() throws {
        guard fileManager.fileExists(atPath: launchAgentURL.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: launchAgentURL)
        } catch {
            throw LaunchAtLoginError.removeFailed
        }
    }

    private func resolveExecutablePath() -> String? {
        if let path = Bundle.main.executableURL?.path, fileManager.fileExists(atPath: path) {
            return path
        }

        let fallback = CommandLine.arguments.first ?? ""
        if !fallback.isEmpty {
            let absolute: String
            if fallback.hasPrefix("/") {
                absolute = fallback
            } else {
                absolute = URL(fileURLWithPath: fileManager.currentDirectoryPath)
                    .appendingPathComponent(fallback)
                    .path
            }
            if fileManager.fileExists(atPath: absolute) {
                return absolute
            }
        }
        return nil
    }
}
