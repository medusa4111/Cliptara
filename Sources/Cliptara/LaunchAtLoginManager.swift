import Foundation

enum LaunchAtLoginError: LocalizedError {
    case executableNotFound
    case writeFailed
    case removeFailed

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
        }
    }
}

final class LaunchAtLoginManager {
    private let fileManager = FileManager.default

    func isEnabled() -> Bool {
        fileManager.fileExists(atPath: launchAgentURL.path)
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else {
            try removeLaunchAgent()
        }
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
