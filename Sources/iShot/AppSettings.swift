import Foundation

final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "appLanguage"
        static let muteScreenshotSound = "muteScreenshotSound"
        static let videoAudioMode = "videoAudioMode"
        static let hotkeys = "hotkeys"
        static let screenshotAction = "screenshotAction"
        static let screenshotsDirectory = "screenshotsDirectory"
        static let videosDirectory = "videosDirectory"
    }

    private let defaults = UserDefaults.standard

    private(set) var language: AppLanguage
    private(set) var muteScreenshotSound: Bool
    private(set) var videoAudioMode: AudioCaptureMode
    private(set) var hotkeys: HotkeyConfiguration
    private(set) var screenshotAction: ScreenshotAction
    private(set) var screenshotsDirectory: URL
    private(set) var videosDirectory: URL

    private init() {
        let defaultRoot = Self.defaultMaterialsRoot()
        let defaultScreenshotsDirectory = defaultRoot.appendingPathComponent("Screenshots", isDirectory: true)
        let legacyScreenshotsDirectory = defaultRoot.appendingPathComponent("Scrinshots", isDirectory: true)
        let defaultVideosDirectory = defaultRoot.appendingPathComponent("Videos", isDirectory: true)

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

        if screenshotsDirectory.lastPathComponent == "Scrinshots" {
            screenshotsDirectory = defaultScreenshotsDirectory
            defaults.set(screenshotsDirectory.path, forKey: Keys.screenshotsDirectory)
        }

        if FileManager.default.fileExists(atPath: legacyScreenshotsDirectory.path),
           !FileManager.default.fileExists(atPath: defaultScreenshotsDirectory.path) {
            try? FileManager.default.moveItem(at: legacyScreenshotsDirectory, to: defaultScreenshotsDirectory)
        }

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
        return documents.appendingPathComponent("ishotmaterials", isDirectory: true)
    }
}
