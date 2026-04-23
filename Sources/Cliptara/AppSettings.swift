import Foundation

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "appLanguage"
        static let muteScreenshotSound = "muteScreenshotSound"
        static let videoAudioMode = "videoAudioMode"
        static let hotkeys = "hotkeys"
        static let screenshotAction = "screenshotAction"
        static let screenshotFileFormat = "screenshotFileFormat"
        static let videoTargetBitrateKbps = "videoTargetBitrateKbps"
        static let screenshotsDirectory = "screenshotsDirectory"
        static let videosDirectory = "videosDirectory"
    }

    private let defaults = UserDefaults.standard

    private(set) var language: AppLanguage
    private(set) var muteScreenshotSound: Bool
    private(set) var videoAudioMode: AudioCaptureMode
    private(set) var hotkeys: HotkeyConfiguration
    private(set) var screenshotAction: ScreenshotAction
    private(set) var screenshotFileFormat: ScreenshotFileFormat
    private(set) var videoTargetBitrateKbps: Int
    private(set) var screenshotsDirectory: URL
    private(set) var videosDirectory: URL

    private init() {
        let defaultRoot = Self.defaultMaterialsRoot()
        let legacyRoot = Self.legacyMaterialsRoot()
        let defaultScreenshotsDirectory = defaultRoot.appendingPathComponent("Screenshots", isDirectory: true)
        let defaultVideosDirectory = defaultRoot.appendingPathComponent("Videos", isDirectory: true)
        let legacyScreenshotsDirectory = legacyRoot.appendingPathComponent("Screenshots", isDirectory: true)
        let legacyScreenshotsTypoDirectory = legacyRoot.appendingPathComponent("Scrinshots", isDirectory: true)
        let legacyVideosDirectory = legacyRoot.appendingPathComponent("Videos", isDirectory: true)

        if let raw = defaults.string(forKey: Keys.language),
           let parsed = AppLanguage(rawValue: raw) {
            language = parsed
        } else {
            language = AppLanguage.defaultFromSystem
            defaults.set(language.rawValue, forKey: Keys.language)
        }

        muteScreenshotSound = defaults.object(forKey: Keys.muteScreenshotSound) as? Bool ?? false

        if let raw = defaults.string(forKey: Keys.videoAudioMode),
           let parsed = AudioCaptureMode(rawValue: raw) {
            videoAudioMode = parsed
        } else {
            videoAudioMode = .system
            defaults.set(videoAudioMode.rawValue, forKey: Keys.videoAudioMode)
        }

        if let data = defaults.data(forKey: Keys.hotkeys),
           let decoded = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = .default
            if let data = try? JSONEncoder().encode(hotkeys) {
                defaults.set(data, forKey: Keys.hotkeys)
            }
        }

        if let raw = defaults.string(forKey: Keys.screenshotAction),
           let parsed = ScreenshotAction(rawValue: raw) {
            screenshotAction = parsed
        } else {
            screenshotAction = .copyToClipboard
            defaults.set(screenshotAction.rawValue, forKey: Keys.screenshotAction)
        }

        if let raw = defaults.string(forKey: Keys.screenshotFileFormat),
           let parsed = ScreenshotFileFormat(rawValue: raw) {
            screenshotFileFormat = parsed
        } else {
            screenshotFileFormat = .png
            defaults.set(screenshotFileFormat.rawValue, forKey: Keys.screenshotFileFormat)
        }

        let storedBitrate = defaults.object(forKey: Keys.videoTargetBitrateKbps) as? Int
            ?? defaults.integer(forKey: Keys.videoTargetBitrateKbps)
        if storedBitrate > 0 {
            videoTargetBitrateKbps = Self.clampedBitrateKbps(storedBitrate)
        } else {
            videoTargetBitrateKbps = 6000
        }
        defaults.set(videoTargetBitrateKbps, forKey: Keys.videoTargetBitrateKbps)

        if let path = defaults.string(forKey: Keys.screenshotsDirectory), !path.isEmpty {
            screenshotsDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            screenshotsDirectory = defaultScreenshotsDirectory
            defaults.set(screenshotsDirectory.path, forKey: Keys.screenshotsDirectory)
        }

        if let path = defaults.string(forKey: Keys.videosDirectory), !path.isEmpty {
            videosDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            videosDirectory = defaultVideosDirectory
            defaults.set(videosDirectory.path, forKey: Keys.videosDirectory)
        }

        if screenshotsDirectory.lastPathComponent == "Scrinshots" || screenshotsDirectory.path == legacyScreenshotsTypoDirectory.path {
            screenshotsDirectory = defaultScreenshotsDirectory
            defaults.set(screenshotsDirectory.path, forKey: Keys.screenshotsDirectory)
        }

        if screenshotsDirectory.path == legacyScreenshotsDirectory.path {
            screenshotsDirectory = defaultScreenshotsDirectory
            defaults.set(screenshotsDirectory.path, forKey: Keys.screenshotsDirectory)
        }

        if videosDirectory.path == legacyVideosDirectory.path {
            videosDirectory = defaultVideosDirectory
            defaults.set(videosDirectory.path, forKey: Keys.videosDirectory)
        }

        migrateLegacyMaterials(
            legacyRoot: legacyRoot,
            defaultRoot: defaultRoot,
            legacyScreenshotsDirectory: legacyScreenshotsDirectory,
            legacyScreenshotsTypoDirectory: legacyScreenshotsTypoDirectory,
            legacyVideosDirectory: legacyVideosDirectory,
            defaultScreenshotsDirectory: defaultScreenshotsDirectory,
            defaultVideosDirectory: defaultVideosDirectory
        )

        ensureMaterialsDirectories()
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: Keys.language)
    }

    func setMuteScreenshotSound(_ value: Bool) {
        muteScreenshotSound = value
        defaults.set(value, forKey: Keys.muteScreenshotSound)
    }

    func setVideoAudioMode(_ mode: AudioCaptureMode) {
        videoAudioMode = mode
        defaults.set(mode.rawValue, forKey: Keys.videoAudioMode)
    }

    func setHotkeys(_ hotkeys: HotkeyConfiguration) {
        self.hotkeys = hotkeys
        persistHotkeys()
    }

    func setScreenshotAction(_ action: ScreenshotAction) {
        screenshotAction = action
        defaults.set(action.rawValue, forKey: Keys.screenshotAction)
    }

    func setScreenshotFileFormat(_ format: ScreenshotFileFormat) {
        screenshotFileFormat = format
        defaults.set(format.rawValue, forKey: Keys.screenshotFileFormat)
    }

    func setVideoTargetBitrateKbps(_ bitrateKbps: Int) {
        videoTargetBitrateKbps = Self.clampedBitrateKbps(bitrateKbps)
        defaults.set(videoTargetBitrateKbps, forKey: Keys.videoTargetBitrateKbps)
    }

    func setScreenshotsDirectory(_ url: URL) {
        screenshotsDirectory = url
        defaults.set(url.path, forKey: Keys.screenshotsDirectory)
        ensureMaterialsDirectories()
    }

    func setVideosDirectory(_ url: URL) {
        videosDirectory = url
        defaults.set(url.path, forKey: Keys.videosDirectory)
        ensureMaterialsDirectories()
    }

    func ensureMaterialsDirectories() {
        try? FileManager.default.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
    }

    private func persistHotkeys() {
        if let data = try? JSONEncoder().encode(hotkeys) {
            defaults.set(data, forKey: Keys.hotkeys)
        }
    }

    private static func defaultMaterialsRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("cliptaramaterials", isDirectory: true)
    }

    private static func legacyMaterialsRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        let legacyFolderName = ["i", "s", "h", "o", "t", "m", "a", "t", "e", "r", "i", "a", "l", "s"].joined()
        return documents.appendingPathComponent(legacyFolderName, isDirectory: true)
    }

    private static func clampedBitrateKbps(_ value: Int) -> Int {
        min(max(value, 800), 50_000)
    }

    private func migrateLegacyMaterials(
        legacyRoot: URL,
        defaultRoot: URL,
        legacyScreenshotsDirectory: URL,
        legacyScreenshotsTypoDirectory: URL,
        legacyVideosDirectory: URL,
        defaultScreenshotsDirectory: URL,
        defaultVideosDirectory: URL
    ) {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: legacyRoot.path),
           !fileManager.fileExists(atPath: defaultRoot.path) {
            try? fileManager.moveItem(at: legacyRoot, to: defaultRoot)
            return
        }

        if fileManager.fileExists(atPath: legacyScreenshotsTypoDirectory.path),
           !fileManager.fileExists(atPath: defaultScreenshotsDirectory.path) {
            try? fileManager.moveItem(at: legacyScreenshotsTypoDirectory, to: defaultScreenshotsDirectory)
        }

        if fileManager.fileExists(atPath: legacyScreenshotsDirectory.path),
           !fileManager.fileExists(atPath: defaultScreenshotsDirectory.path) {
            try? fileManager.moveItem(at: legacyScreenshotsDirectory, to: defaultScreenshotsDirectory)
        }

        if fileManager.fileExists(atPath: legacyVideosDirectory.path),
           !fileManager.fileExists(atPath: defaultVideosDirectory.path) {
            try? fileManager.moveItem(at: legacyVideosDirectory, to: defaultVideosDirectory)
        }
    }
}
