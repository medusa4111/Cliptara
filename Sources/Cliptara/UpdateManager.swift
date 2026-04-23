import AppKit
import Foundation

struct RemoteUpdateManifest: Decodable {
    let version: String
    let build: String?
    let downloadURL: URL
    let releaseNotes: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case build
        case downloadURL = "download_url"
        case releaseNotes = "release_notes"
    }
}

enum UpdateCheckResult {
    case upToDate
    case updateAvailable(RemoteUpdateManifest)
}

enum UpdateManagerError: LocalizedError {
    case manifestURLNotConfigured
    case invalidManifestURL
    case updateCheckFailed
    case updatePackageDownloadFailed
    case mountedAppNotFound
    case installScriptLaunchFailed
    case manualInstallRequired(URL)

    var errorDescription: String? {
        switch self {
        case .manifestURLNotConfigured:
            return Localizer.text(
                "URL проверки обновлений не настроен.",
                "Update feed URL is not configured."
            )
        case .invalidManifestURL:
            return Localizer.text(
                "URL проверки обновлений некорректен.",
                "Update feed URL is invalid."
            )
        case .updateCheckFailed:
            return Localizer.text(
                "Не удалось проверить обновления.",
                "Could not check for updates."
            )
        case .updatePackageDownloadFailed:
            return Localizer.text(
                "Не удалось скачать пакет обновления.",
                "Could not download update package."
            )
        case .mountedAppNotFound:
            return Localizer.text(
                "В пакете обновления не найдено приложение Cliptara.app.",
                "Cliptara.app was not found inside the update package."
            )
        case .installScriptLaunchFailed:
            return Localizer.text(
                "Не удалось запустить установку обновления.",
                "Could not start update installer."
            )
        case .manualInstallRequired:
            return Localizer.text(
                "Автоматическая установка недоступна. Откройте пакет обновления вручную.",
                "Automatic installation is unavailable. Open the update package manually."
            )
        }
    }
}

@MainActor
final class UpdateManager {
    private let urlSession = URLSession.shared

    func checkForUpdates() async throws -> UpdateCheckResult {
        let manifestURL = try resolveManifestURL()

        let data: Data
        do {
            let response = try await urlSession.data(from: manifestURL)
            data = response.0
        } catch {
            throw UpdateManagerError.updateCheckFailed
        }

        let manifest: RemoteUpdateManifest
        do {
            manifest = try JSONDecoder().decode(RemoteUpdateManifest.self, from: data)
        } catch {
            throw UpdateManagerError.updateCheckFailed
        }

        let localVersion = currentAppVersion
        let localBuild = Int(currentAppBuild)
        let remoteBuild = manifest.build.flatMap(Int.init)

        if isRemoteNewer(
            localVersion: localVersion,
            localBuild: localBuild,
            remoteVersion: manifest.version,
            remoteBuild: remoteBuild
        ) {
            return .updateAvailable(manifest)
        }

        return .upToDate
    }

    func downloadAndInstall(_ update: RemoteUpdateManifest) async throws {
        let packageURL = try await downloadUpdatePackage(from: update.downloadURL, version: update.version)
        try installFromDMG(packageURL)
    }

    var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentAppBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private func resolveManifestURL() throws -> URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CliptaraUpdateManifestURL") as? String else {
            throw UpdateManagerError.manifestURLNotConfigured
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw UpdateManagerError.manifestURLNotConfigured
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            throw UpdateManagerError.invalidManifestURL
        }
        return url
    }

    private func downloadUpdatePackage(from remoteURL: URL, version: String) async throws -> URL {
        let temporaryDownloadURL: URL
        do {
            let response = try await urlSession.download(from: remoteURL)
            temporaryDownloadURL = response.0
        } catch {
            throw UpdateManagerError.updatePackageDownloadFailed
        }

        let ext = remoteURL.pathExtension.isEmpty ? "dmg" : remoteURL.pathExtension.lowercased()
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cliptara-\(version)-update")
            .appendingPathExtension(ext)

        try? FileManager.default.removeItem(at: targetURL)
        do {
            try FileManager.default.moveItem(at: temporaryDownloadURL, to: targetURL)
            return targetURL
        } catch {
            throw UpdateManagerError.updatePackageDownloadFailed
        }
    }

    private func installFromDMG(_ dmgURL: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("cliptara-update-mount-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        do {
            _ = try runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["attach", dmgURL.path, "-nobrowse", "-noverify", "-mountpoint", mountPoint.path]
            )
        } catch {
            NSWorkspace.shared.open(dmgURL)
            throw UpdateManagerError.manualInstallRequired(dmgURL)
        }

        let sourceAppURL = mountPoint.appendingPathComponent("Cliptara.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sourceAppURL.path) else {
            _ = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            throw UpdateManagerError.mountedAppNotFound
        }

        let destinationAppURL = preferredInstallDestination()
        let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("cliptara-self-update-\(UUID().uuidString).sh")

        let script = """
        #!/bin/zsh
        sleep 1
        /usr/bin/ditto \(shellEscape(sourceAppURL.path)) \(shellEscape(destinationAppURL.path))
        /usr/bin/xattr -dr com.apple.quarantine \(shellEscape(destinationAppURL.path)) >/dev/null 2>&1 || true
        /usr/bin/hdiutil detach \(shellEscape(mountPoint.path)) -force >/dev/null 2>&1 || true
        /usr/bin/open \(shellEscape(destinationAppURL.path))
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            _ = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            throw UpdateManagerError.installScriptLaunchFailed
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [scriptURL.path]
            try process.run()
        } catch {
            _ = try? runProcess(executable: "/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            throw UpdateManagerError.installScriptLaunchFailed
        }

        NSApp.terminate(nil)
    }

    private func preferredInstallDestination() -> URL {
        let currentBundleURL = Bundle.main.bundleURL
        let applicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        if currentBundleURL.path.hasPrefix(applicationsURL.path + "/") {
            return applicationsURL.appendingPathComponent("Cliptara.app", isDirectory: true)
        }

        return currentBundleURL.deletingLastPathComponent().appendingPathComponent("Cliptara.app", isDirectory: true)
    }

    private func isRemoteNewer(
        localVersion: String,
        localBuild: Int?,
        remoteVersion: String,
        remoteBuild: Int?
    ) -> Bool {
        let versionCompare = localVersion.compare(remoteVersion, options: .numeric)
        if versionCompare == .orderedAscending {
            return true
        }
        if versionCompare == .orderedDescending {
            return false
        }

        guard let localBuild, let remoteBuild else {
            return false
        }
        return remoteBuild > localBuild
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String]) throws -> (code: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData + errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "UpdateProcessError",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output]
            )
        }
        return (process.terminationStatus, output)
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
