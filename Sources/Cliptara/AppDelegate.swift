import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    private let settings = AppSettings.shared
    private let hotkeyManager = HotkeyManager()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let screenshotController = ScreenshotController()
    private let flashController = ScreenFlashController.shared
    private let screenRecorder = ScreenRecorder()
    private let updateManager = UpdateManager()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var settingsMenuItem: NSMenuItem?
    private var checkUpdatesMenuItem: NSMenuItem?
    private var openScreenshotsFolderMenuItem: NSMenuItem?
    private var openVideosFolderMenuItem: NSMenuItem?
    private var compressVideoMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?

    private var settingsWindowController: SettingsWindowController?
    private var videoCompressionWindowController: VideoCompressionWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        settings.ensureMaterialsDirectories()

        buildStatusMenu()
        setupSettingsWindow()
        setupVideoCompressionWindow()
        configureHotkeys()
        applyStoredLaunchAtLoginState()

        screenRecorder.onRecordingStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.setStatusItemRecordingState(state: state)
            }
        }

        refreshMenuLocalization()
        setStatusItemRecordingState(state: .idle)
    }

    private func buildStatusMenu() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let checkUpdatesItem = NSMenuItem(title: "", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        let openScreenshotsFolderItem = NSMenuItem(title: "", action: #selector(openScreenshotsFolder), keyEquivalent: "")
        openScreenshotsFolderItem.target = self
        menu.addItem(openScreenshotsFolderItem)

        let openVideosFolderItem = NSMenuItem(title: "", action: #selector(openVideosFolder), keyEquivalent: "")
        openVideosFolderItem.target = self
        menu.addItem(openVideosFolderItem)

        let compressVideoItem = NSMenuItem(title: "", action: #selector(openVideoCompressor), keyEquivalent: "")
        compressVideoItem.target = self
        menu.addItem(compressVideoItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        self.statusItem = statusItem
        self.statusMenu = menu
        self.settingsMenuItem = settingsItem
        self.checkUpdatesMenuItem = checkUpdatesItem
        self.openScreenshotsFolderMenuItem = openScreenshotsFolderItem
        self.openVideosFolderMenuItem = openVideosFolderItem
        self.compressVideoMenuItem = compressVideoItem
        self.quitMenuItem = quitItem
    }

    private func setupSettingsWindow() {
        let controller = SettingsWindowController(settings: settings)

        controller.onAreaHotkeyChanged = { [weak self] hotkey in
            guard let self else { return false }
            var config = settings.hotkeys
            config.areaCapture = hotkey
            return tryApplyHotkeys(config)
        }

        controller.onFullHotkeyChanged = { [weak self] hotkey in
            guard let self else { return false }
            var config = settings.hotkeys
            config.fullCapture = hotkey
            return tryApplyHotkeys(config)
        }

        controller.onVideoHotkeyChanged = { [weak self] hotkey in
            guard let self else { return false }
            var config = settings.hotkeys
            config.videoToggle = hotkey
            return tryApplyHotkeys(config)
        }

        controller.onVideoPauseResumeHotkeyChanged = { [weak self] hotkey in
            guard let self else { return false }
            var config = settings.hotkeys
            config.videoPauseResume = hotkey
            return tryApplyHotkeys(config)
        }

        controller.onLanguageChanged = { [weak self] language in
            guard let self else { return }
            settings.setLanguage(language)
            refreshMenuLocalization()
            settingsWindowController?.refreshLocalization()
        }

        controller.onScreenshotActionChanged = { [weak self] action in
            self?.settings.setScreenshotAction(action)
        }

        controller.onScreenshotFormatChanged = { [weak self] format in
            self?.settings.setScreenshotFileFormat(format)
        }

        controller.onMuteScreenshotSoundChanged = { [weak self] value in
            self?.settings.setMuteScreenshotSound(value)
        }

        controller.onLaunchAtLoginChanged = { [weak self] enabled in
            self?.setLaunchAtLogin(enabled)
        }

        controller.onVideoFileFormatChanged = { [weak self] format in
            self?.settings.setVideoFileFormat(format)
        }

        controller.onVideoCodecChanged = { [weak self] codec in
            self?.settings.setVideoCodec(codec)
        }

        controller.onVideoFrameRateChanged = { [weak self] frameRate in
            self?.settings.setVideoFrameRate(frameRate)
        }

        controller.onVideoQualityPresetChanged = { [weak self] preset in
            self?.settings.setVideoQualityPreset(preset)
            self?.settingsWindowController?.reloadFromSettings()
        }

        controller.onVideoStartDelayChanged = { [weak self] delay in
            self?.settings.setVideoStartDelaySeconds(delay.rawValue)
        }

        controller.onVideoAudioModeChanged = { [weak self] mode in
            self?.settings.setVideoAudioMode(mode)
        }

        controller.onVideoShowCursorChanged = { [weak self] value in
            self?.settings.setVideoShowCursor(value)
        }

        controller.onAutoOpenRecordedVideoChanged = { [weak self] value in
            self?.settings.setAutoOpenRecordedVideo(value)
        }

        controller.onChooseScreenshotsDirectory = { [weak self] in
            self?.chooseScreenshotsDirectory()
        }

        controller.onChooseVideosDirectory = { [weak self] in
            self?.chooseVideosDirectory()
        }

        settingsWindowController = controller
        settingsWindowController?.window?.delegate = self
    }

    private func setupVideoCompressionWindow() {
        videoCompressionWindowController = VideoCompressionWindowController(settings: settings)
    }

    private func configureHotkeys() {
        hotkeyManager.onAreaCapture = { [weak self] in
            Task { @MainActor in
                await self?.handleAreaScreenshotHotkey()
            }
        }

        hotkeyManager.onFullCapture = { [weak self] in
            Task { @MainActor in
                await self?.handleFullScreenshotHotkey()
            }
        }

        hotkeyManager.onVideoToggle = { [weak self] in
            Task { @MainActor in
                await self?.handleVideoToggleHotkey()
            }
        }

        hotkeyManager.onVideoPauseResume = { [weak self] in
            Task { @MainActor in
                await self?.handleVideoPauseResumeHotkey()
            }
        }

        hotkeyManager.registerHotkeys(configuration: settings.hotkeys)
    }

    private func tryApplyHotkeys(_ configuration: HotkeyConfiguration) -> Bool {
        if let conflictMessage = validateHotkeyConflicts(configuration) {
            showErrorAlert(
                title: Localizer.text("Конфликт горячих клавиш", "Hotkey conflict"),
                message: conflictMessage
            )
            return false
        }

        settings.setHotkeys(configuration)
        hotkeyManager.registerHotkeys(configuration: configuration)
        return true
    }

    private func validateHotkeyConflicts(_ configuration: HotkeyConfiguration) -> String? {
        if configuration.areaCapture.matches(configuration.fullCapture) {
            return Localizer.text(
                "Горячие клавиши для области и полного экрана не должны совпадать.",
                "Area and full-screen hotkeys must be different."
            )
        }

        if configuration.areaCapture.matches(configuration.videoToggle) {
            return Localizer.text(
                "Горячая клавиша области конфликтует с горячей клавишей видео.",
                "Area hotkey conflicts with video hotkey."
            )
        }

        if configuration.fullCapture.matches(configuration.videoToggle) {
            return Localizer.text(
                "Горячая клавиша полного экрана конфликтует с горячей клавишей видео.",
                "Full-screen hotkey conflicts with video hotkey."
            )
        }

        if configuration.videoPauseResume.matches(configuration.areaCapture) {
            return Localizer.text(
                "Горячая клавиша паузы видео конфликтует с горячей клавишей области.",
                "Video pause hotkey conflicts with area hotkey."
            )
        }

        if configuration.videoPauseResume.matches(configuration.fullCapture) {
            return Localizer.text(
                "Горячая клавиша паузы видео конфликтует с горячей клавишей полного экрана.",
                "Video pause hotkey conflicts with full-screen hotkey."
            )
        }

        if configuration.videoPauseResume.matches(configuration.videoToggle) {
            return Localizer.text(
                "Горячие клавиши старт/стоп и пауза/продолжить не должны совпадать.",
                "Start/stop and pause/resume hotkeys must be different."
            )
        }

        return nil
    }

    private func handleAreaScreenshotHotkey() async {
        closeStatusMenuIfNeeded()
        try? await Task.sleep(nanoseconds: 180_000_000)

        do {
            _ = try await screenshotController.captureSelectedArea(
                action: settings.screenshotAction,
                format: settings.screenshotFileFormat,
                muteSound: settings.muteScreenshotSound,
                directory: settings.screenshotsDirectory
            )
        } catch {
            showErrorAlert(
                title: Localizer.text("Ошибка скриншота", "Screenshot Error"),
                message: error.localizedDescription
            )
        }
    }

    private func handleFullScreenshotHotkey() async {
        do {
            _ = try await screenshotController.captureFullScreen(
                action: settings.screenshotAction,
                format: settings.screenshotFileFormat,
                muteSound: settings.muteScreenshotSound,
                directory: settings.screenshotsDirectory
            )
            flashController.flash()
        } catch {
            showErrorAlert(
                title: Localizer.text("Ошибка скриншота", "Screenshot Error"),
                message: error.localizedDescription
            )
        }
    }

    private func handleVideoToggleHotkey() async {
        if screenRecorder.isStopInProgress {
            return
        }

        if screenRecorder.isRecording {
            do {
                let outputURL = try await screenRecorder.stopRecording()
                if settings.autoOpenRecordedVideo {
                    NSWorkspace.shared.open(outputURL)
                }
            } catch {
                if let recorderError = error as? ScreenRecorderError, recorderError == .stopInProgress {
                    return
                }
                showErrorAlert(
                    title: Localizer.text("Ошибка записи видео", "Video Recording Error"),
                    message: error.localizedDescription
                )
            }
            return
        }

        do {
            let countdown = settings.videoStartDelaySeconds
            if countdown > 0 {
                try? await Task.sleep(nanoseconds: UInt64(countdown) * 1_000_000_000)
            }

            _ = try await screenRecorder.startRecording(
                audioMode: settings.videoAudioMode,
                targetBitrateKbps: settings.videoQualityPreset.targetBitrateKbps,
                outputDirectory: settings.videosDirectory,
                fileFormat: settings.videoFileFormat,
                codec: settings.videoCodec,
                frameRate: settings.videoFrameRate,
                showCursor: settings.videoShowCursor
            )
        } catch {
            showErrorAlert(
                title: Localizer.text("Ошибка записи видео", "Video Recording Error"),
                message: error.localizedDescription
            )
        }
    }

    private func handleVideoPauseResumeHotkey() async {
        if screenRecorder.isStopInProgress || !screenRecorder.isRecording {
            return
        }

        do {
            if screenRecorder.isPaused {
                try await screenRecorder.resumeRecording()
            } else {
                try await screenRecorder.pauseRecording()
            }
        } catch {
            if let recorderError = error as? ScreenRecorderError, recorderError == .stopInProgress {
                return
            }
            showErrorAlert(
                title: Localizer.text("Ошибка записи видео", "Video Recording Error"),
                message: error.localizedDescription
            )
        }
    }

    private func setStatusItemRecordingState(state: ScreenRecordingState) {
        guard let button = statusItem?.button else {
            return
        }

        let symbolName: String
        let tintColor: NSColor?
        switch state {
        case .idle:
            symbolName = "camera.viewfinder"
            tintColor = nil
        case .recording:
            symbolName = "record.circle.fill"
            tintColor = .systemRed
        case .paused:
            symbolName = "pause.circle.fill"
            tintColor = .systemOrange
        }

        if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            symbol.isTemplate = (state == .idle)
            button.image = symbol
            button.contentTintColor = tintColor
            button.title = ""
        } else {
            button.contentTintColor = nil
            button.image = nil
            button.title = "Cliptara"
        }
    }

    private func refreshMenuLocalization() {
        settingsMenuItem?.title = Localizer.text("Настройки", "Settings")
        checkUpdatesMenuItem?.title = Localizer.text("Проверить обновления…", "Check for updates…")
        openScreenshotsFolderMenuItem?.title = Localizer.text("Открыть папку со скриншотами", "Open screenshots folder")
        openVideosFolderMenuItem?.title = Localizer.text("Открыть папку с видео", "Open videos folder")
        compressVideoMenuItem?.title = Localizer.text("Уменьшить размер видеофайла", "Reduce video file size")
        quitMenuItem?.title = Localizer.text("Выход", "Quit")

        if let button = statusItem?.button {
            button.toolTip = Localizer.text(
                "Cliptara: Ctrl+` область, Ctrl+1 экран, Ctrl+2 старт/стоп, Ctrl+3 пауза/продолжить",
                "Cliptara: Ctrl+` area, Ctrl+1 screen, Ctrl+2 start/stop, Ctrl+3 pause/resume"
            )
        }
    }

    @objc
    private func openSettings() {
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func checkForUpdatesAction() {
        Task { @MainActor in
            await checkForUpdates(interactive: true)
        }
    }

    @objc
    private func openScreenshotsFolder() {
        settings.ensureMaterialsDirectories()
        NSWorkspace.shared.open(settings.screenshotsDirectory)
    }

    @objc
    private func openVideosFolder() {
        settings.ensureMaterialsDirectories()
        NSWorkspace.shared.open(settings.videosDirectory)
    }

    @objc
    private func openVideoCompressor() {
        videoCompressionWindowController?.refreshLocalization()
        videoCompressionWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: Localizer.text("OK", "OK"))
        alert.runModal()
    }

    private func closeStatusMenuIfNeeded() {
        guard let statusItem, let menu = statusMenu else {
            return
        }

        menu.cancelTracking()
        if statusItem.menu != nil {
            statusItem.menu = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                statusItem.menu = self.statusMenu
            }
        }
    }

    private func chooseScreenshotsDirectory() {
        let panel = NSOpenPanel()
        panel.title = Localizer.text("Выберите папку для скриншотов", "Choose screenshots folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.screenshotsDirectory

        if panel.runModal() == .OK, let url = panel.url {
            settings.setScreenshotsDirectory(url)
            settingsWindowController?.reloadFromSettings()
        }
    }

    private func chooseVideosDirectory() {
        let panel = NSOpenPanel()
        panel.title = Localizer.text("Выберите папку для видео", "Choose videos folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.videosDirectory

        if panel.runModal() == .OK, let url = panel.url {
            settings.setVideosDirectory(url)
            settingsWindowController?.reloadFromSettings()
        }
    }

    private func checkForUpdates(interactive: Bool) async {
        do {
            let result = try await updateManager.checkForUpdates()
            switch result {
            case .upToDate:
                if interactive {
                    showInfoAlert(
                        title: Localizer.text("Обновления", "Updates"),
                        message: Localizer.text("У вас уже установлена последняя версия.", "You already have the latest version.")
                    )
                }
            case .updateAvailable(let update):
                await promptAndInstall(update)
            }
        } catch {
            if interactive {
                showErrorAlert(
                    title: Localizer.text("Ошибка проверки обновлений", "Update Check Error"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func promptAndInstall(_ update: RemoteUpdateManifest) async {
        let notes = update.releaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let message = Localizer.text(
            "Найдена новая версия \(update.version).\nТекущая версия: \(updateManager.currentAppVersion).",
            "A new version \(update.version) is available.\nCurrent version: \(updateManager.currentAppVersion)."
        )
        let details = notes.isEmpty ? message : "\(message)\n\n\(notes)"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = Localizer.text("Доступно обновление", "Update Available")
        alert.informativeText = details
        alert.addButton(withTitle: Localizer.text("Установить обновление", "Install Update"))
        alert.addButton(withTitle: Localizer.text("Позже", "Later"))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        do {
            try await updateManager.downloadAndInstall(update)
        } catch let updateError as UpdateManagerError {
            switch updateError {
            case .manualInstallRequired(let packageURL):
                NSWorkspace.shared.open(packageURL)
                showInfoAlert(
                    title: Localizer.text("Ручная установка", "Manual Installation"),
                    message: Localizer.text(
                        "Автоустановка недоступна. Открыл пакет обновления, установите приложение вручную.",
                        "Automatic install is unavailable. The update package was opened, install manually."
                    )
                )
            default:
                showErrorAlert(
                    title: Localizer.text("Ошибка обновления", "Update Error"),
                    message: updateError.localizedDescription
                )
            }
        } catch {
            showErrorAlert(
                title: Localizer.text("Ошибка обновления", "Update Error"),
                message: error.localizedDescription
            )
        }
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: Localizer.text("OK", "OK"))
        alert.runModal()
    }

    private func applyStoredLaunchAtLoginState() {
        do {
            try launchAtLoginManager.setEnabled(settings.launchAtLogin)
        } catch {
            settings.setLaunchAtLogin(false)
        }
        settings.setLaunchAtLogin(launchAtLoginManager.isEnabled())
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            settings.setLaunchAtLogin(launchAtLoginManager.isEnabled())
        } catch {
            settings.setLaunchAtLogin(launchAtLoginManager.isEnabled())
            settingsWindowController?.reloadFromSettings()
            showErrorAlert(
                title: Localizer.text("Автозапуск", "Launch at Login"),
                message: error.localizedDescription
            )
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard isSettingsWindow(notification.object) else {
            return
        }
        hotkeyManager.setEnabled(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isSettingsWindow(notification.object) else {
            return
        }
        hotkeyManager.setEnabled(true)
    }

    func windowWillClose(_ notification: Notification) {
        guard isSettingsWindow(notification.object) else {
            return
        }
        hotkeyManager.setEnabled(true)
    }

    private func isSettingsWindow(_ object: Any?) -> Bool {
        guard let window = object as? NSWindow else {
            return false
        }
        return window === settingsWindowController?.window
    }
}
