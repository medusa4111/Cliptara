import AppKit
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController {
    var onAreaHotkeyChanged: ((Hotkey) -> Bool)?
    var onFullHotkeyChanged: ((Hotkey) -> Bool)?
    var onVideoHotkeyChanged: ((Hotkey) -> Bool)?
    var onVideoPauseResumeHotkeyChanged: ((Hotkey) -> Bool)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onScreenshotActionChanged: ((ScreenshotAction) -> Void)?
    var onScreenshotFormatChanged: ((ScreenshotFileFormat) -> Void)?
    var onMuteScreenshotSoundChanged: ((Bool) -> Void)?
    var onLaunchAtLoginChanged: ((Bool) -> Void)?
    var onVideoFileFormatChanged: ((VideoFileFormat) -> Void)?
    var onVideoCodecChanged: ((VideoCodecOption) -> Void)?
    var onVideoFrameRateChanged: ((VideoFrameRateOption) -> Void)?
    var onVideoQualityPresetChanged: ((VideoQualityPreset) -> Void)?
    var onVideoStartDelayChanged: ((VideoStartDelayOption) -> Void)?
    var onVideoAudioModeChanged: ((AudioCaptureMode) -> Void)?
    var onVideoShowCursorChanged: ((Bool) -> Void)?
    var onAutoOpenRecordedVideoChanged: ((Bool) -> Void)?
    var onChooseScreenshotsDirectory: (() -> Void)?
    var onChooseVideosDirectory: (() -> Void)?

    private let tabView = NSTabView(frame: .zero)
    private let mainTabItem = NSTabViewItem(identifier: "main")
    private let videoTabItem = NSTabViewItem(identifier: "video")

    private let areaLabel = NSTextField(labelWithString: "")
    private let fullLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let screenshotActionLabel = NSTextField(labelWithString: "")
    private let screenshotFormatLabel = NSTextField(labelWithString: "")
    private let muteSoundLabel = NSTextField(labelWithString: "")
    private let launchAtLoginLabel = NSTextField(labelWithString: "")
    private let screenshotsFolderLabel = NSTextField(labelWithString: "")

    private let videoStartStopLabel = NSTextField(labelWithString: "")
    private let videoPauseResumeLabel = NSTextField(labelWithString: "")
    private let videoFileFormatLabel = NSTextField(labelWithString: "")
    private let videoCodecLabel = NSTextField(labelWithString: "")
    private let videoFrameRateLabel = NSTextField(labelWithString: "")
    private let videoQualityLabel = NSTextField(labelWithString: "")
    private let videoStartDelayLabel = NSTextField(labelWithString: "")
    private let videoAudioLabel = NSTextField(labelWithString: "")
    private let videoShowCursorLabel = NSTextField(labelWithString: "")
    private let autoOpenVideoLabel = NSTextField(labelWithString: "")
    private let videosFolderLabel = NSTextField(labelWithString: "")

    private let footerLabel = NSTextField(labelWithString: "")
    private let donateButton = NSButton(title: "", target: nil, action: nil)

    private let areaField: HotkeyRecorderField
    private let fullField: HotkeyRecorderField
    private let videoStartStopField: HotkeyRecorderField
    private let videoPauseResumeField: HotkeyRecorderField

    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let muteSoundSwitch = NSSwitch(frame: .zero)
    private let launchAtLoginSwitch = NSSwitch(frame: .zero)
    private let videoFileFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoCodecPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoFrameRatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoQualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoStartDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoAudioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoShowCursorSwitch = NSSwitch(frame: .zero)
    private let autoOpenVideoSwitch = NSSwitch(frame: .zero)

    private let screenshotsPathField = NSTextField(labelWithString: "")
    private let videosPathField = NSTextField(labelWithString: "")
    private let chooseScreenshotsButton = NSButton(title: "", target: nil, action: nil)
    private let chooseVideosButton = NSButton(title: "", target: nil, action: nil)

    private let languageOptions: [AppLanguage] = [
        .russian,
        .english,
        .german,
        .french,
        .spanish,
        .chineseSimplified,
        .chineseTraditional,
        .arabic
    ]
    private let screenshotActionOptions: [ScreenshotAction] = [.copyToClipboard, .saveToFiles]
    private let screenshotFormatOptions: [ScreenshotFileFormat] = [.png, .jpg, .webp]
    private let videoAudioOptions: [AudioCaptureMode] = [.system, .silent]
    private let videoFileFormatOptions = VideoFileFormat.allCases
    private let videoCodecOptions = VideoCodecOption.allCases
    private let videoFrameRateOptions = VideoFrameRateOption.allCases
    private let videoQualityOptions = VideoQualityPreset.allCases
    private let videoStartDelayOptions = VideoStartDelayOption.allCases

    init(settings: AppSettings) {
        areaField = HotkeyRecorderField(hotkey: settings.hotkeys.areaCapture)
        fullField = HotkeyRecorderField(hotkey: settings.hotkeys.fullCapture)
        videoStartStopField = HotkeyRecorderField(hotkey: settings.hotkeys.videoToggle)
        videoPauseResumeField = HotkeyRecorderField(hotkey: settings.hotkeys.videoPauseResume)

        super.init(window: nil)

        buildWindow()
        bindActions()
        reloadFromSettings()
        refreshLocalization()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func reloadFromSettings() {
        let settings = AppSettings.shared

        areaField.hotkey = settings.hotkeys.areaCapture
        fullField.hotkey = settings.hotkeys.fullCapture
        videoStartStopField.hotkey = settings.hotkeys.videoToggle
        videoPauseResumeField.hotkey = settings.hotkeys.videoPauseResume

        muteSoundSwitch.state = settings.muteScreenshotSound ? .on : .off
        launchAtLoginSwitch.state = settings.launchAtLogin ? .on : .off
        videoShowCursorSwitch.state = settings.videoShowCursor ? .on : .off
        autoOpenVideoSwitch.state = settings.autoOpenRecordedVideo ? .on : .off

        if let languageIndex = languageOptions.firstIndex(of: settings.language) {
            languagePopup.selectItem(at: languageIndex)
        }
        if let actionIndex = screenshotActionOptions.firstIndex(of: settings.screenshotAction) {
            screenshotActionPopup.selectItem(at: actionIndex)
        }
        if let formatIndex = screenshotFormatOptions.firstIndex(of: settings.screenshotFileFormat) {
            screenshotFormatPopup.selectItem(at: formatIndex)
        }
        if let formatIndex = videoFileFormatOptions.firstIndex(of: settings.videoFileFormat) {
            videoFileFormatPopup.selectItem(at: formatIndex)
        }
        if let codecIndex = videoCodecOptions.firstIndex(of: settings.videoCodec) {
            videoCodecPopup.selectItem(at: codecIndex)
        }
        if let frameRateIndex = videoFrameRateOptions.firstIndex(of: settings.videoFrameRate) {
            videoFrameRatePopup.selectItem(at: frameRateIndex)
        }
        if let qualityIndex = videoQualityOptions.firstIndex(of: settings.videoQualityPreset) {
            videoQualityPopup.selectItem(at: qualityIndex)
        }
        if let delayOption = VideoStartDelayOption(rawValue: settings.videoStartDelaySeconds),
           let delayIndex = videoStartDelayOptions.firstIndex(of: delayOption) {
            videoStartDelayPopup.selectItem(at: delayIndex)
        }
        if let audioIndex = videoAudioOptions.firstIndex(of: settings.videoAudioMode) {
            videoAudioPopup.selectItem(at: audioIndex)
        }

        screenshotsPathField.stringValue = settings.screenshotsDirectory.path
        videosPathField.stringValue = settings.videosDirectory.path
    }

    func refreshLocalization() {
        window?.title = Localizer.text("Настройки Cliptara", "Cliptara Settings")
        mainTabItem.label = Localizer.text("Основное", "General")
        videoTabItem.label = Localizer.text("Видео", "Video")

        areaLabel.stringValue = Localizer.text("Скриншот области:", "Area screenshot:")
        fullLabel.stringValue = Localizer.text("Скриншот экрана:", "Screen screenshot:")
        languageLabel.stringValue = Localizer.text("Язык:", "Language:")
        screenshotActionLabel.stringValue = Localizer.text("Действие скриншота:", "Screenshot action:")
        screenshotFormatLabel.stringValue = Localizer.text("Формат скриншота:", "Screenshot format:")
        muteSoundLabel.stringValue = Localizer.text("Выключить звук скриншота:", "Mute screenshot sound:")
        launchAtLoginLabel.stringValue = Localizer.text("Автозапуск при входе:", "Launch at login:")
        screenshotsFolderLabel.stringValue = Localizer.text("Папка скриншотов:", "Screenshots folder:")

        videoStartStopLabel.stringValue = Localizer.text("Старт/стоп записи:", "Start/stop recording:")
        videoPauseResumeLabel.stringValue = Localizer.text("Пауза/продолжить:", "Pause/resume:")
        videoFileFormatLabel.stringValue = Localizer.text("Формат видео:", "Video format:")
        videoCodecLabel.stringValue = Localizer.text("Кодек видео:", "Video codec:")
        videoFrameRateLabel.stringValue = Localizer.text("Частота кадров:", "Frame rate:")
        videoQualityLabel.stringValue = Localizer.text("Качество видео:", "Video quality:")
        videoStartDelayLabel.stringValue = Localizer.text("Таймер перед стартом:", "Start countdown:")
        videoAudioLabel.stringValue = Localizer.text("Звук видео:", "Video audio:")
        videoShowCursorLabel.stringValue = Localizer.text("Показывать курсор:", "Show cursor:")
        autoOpenVideoLabel.stringValue = Localizer.text("Открывать видео после записи:", "Open video after recording:")
        videosFolderLabel.stringValue = Localizer.text("Папка видео:", "Videos folder:")

        chooseScreenshotsButton.title = Localizer.text("Выбрать", "Choose")
        chooseVideosButton.title = Localizer.text("Выбрать", "Choose")
        donateButton.title = Localizer.text("Донат", "Donate")
        footerLabel.stringValue = "Created by medusa411"

        rebuildLanguagePopupTitles()
        rebuildScreenshotActionPopupTitles()
        rebuildScreenshotFormatPopupTitles()
        rebuildVideoFileFormatPopupTitles()
        rebuildVideoCodecPopupTitles()
        rebuildVideoFrameRatePopupTitles()
        rebuildVideoQualityPopupTitles()
        rebuildVideoStartDelayPopupTitles()
        rebuildVideoAudioPopupTitles()

        reloadFromSettings()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        guard let contentView = window.contentView else {
            return
        }

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.spacing = 12
        rootStack.alignment = .leading
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            rootStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            rootStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .topTabsBezelBorder
        tabView.widthAnchor.constraint(equalToConstant: 700).isActive = true
        tabView.heightAnchor.constraint(equalToConstant: 510).isActive = true

        mainTabItem.view = makeMainTabView(width: 680)
        videoTabItem.view = makeVideoTabView(width: 680)
        tabView.addTabViewItem(mainTabItem)
        tabView.addTabViewItem(videoTabItem)
        rootStack.addArrangedSubview(tabView)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 700).isActive = true
        rootStack.addArrangedSubview(separator)

        donateButton.bezelStyle = .rounded
        donateButton.translatesAutoresizingMaskIntoConstraints = false
        donateButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let donateContainer = NSView(frame: .zero)
        donateContainer.translatesAutoresizingMaskIntoConstraints = false
        donateContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        donateContainer.widthAnchor.constraint(equalToConstant: 700).isActive = true
        donateContainer.addSubview(donateButton)
        NSLayoutConstraint.activate([
            donateButton.centerXAnchor.constraint(equalTo: donateContainer.centerXAnchor),
            donateButton.centerYAnchor.constraint(equalTo: donateContainer.centerYAnchor)
        ])
        rootStack.addArrangedSubview(donateContainer)

        footerLabel.alignment = .center
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.translatesAutoresizingMaskIntoConstraints = false

        let footerContainer = NSView(frame: .zero)
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.heightAnchor.constraint(equalToConstant: 24).isActive = true
        footerContainer.widthAnchor.constraint(equalToConstant: 700).isActive = true
        footerContainer.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerLabel.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            footerLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor)
        ])
        rootStack.addArrangedSubview(footerContainer)
    }

    private func makeMainTabView(width: CGFloat) -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 500))

        let controlsWidth: CGFloat = 300
        let labelsWidth: CGFloat = 250

        areaField.translatesAutoresizingMaskIntoConstraints = false
        fullField.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        screenshotActionPopup.translatesAutoresizingMaskIntoConstraints = false
        screenshotFormatPopup.translatesAutoresizingMaskIntoConstraints = false

        areaField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        fullField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        languagePopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        screenshotActionPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        screenshotFormatPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true

        let muteContainer = makeSwitchContainer(muteSoundSwitch, width: controlsWidth)
        let launchContainer = makeSwitchContainer(launchAtLoginSwitch, width: controlsWidth)
        let screenshotsFolderControl = makeFolderControl(pathField: screenshotsPathField, button: chooseScreenshotsButton, width: controlsWidth)

        let grid = NSGridView(views: [
            [areaLabel, areaField],
            [fullLabel, fullField],
            [languageLabel, languagePopup],
            [screenshotActionLabel, screenshotActionPopup],
            [screenshotFormatLabel, screenshotFormatPopup],
            [muteSoundLabel, muteContainer],
            [launchAtLoginLabel, launchContainer],
            [screenshotsFolderLabel, screenshotsFolderControl]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.column(at: 0).width = labelsWidth
        grid.column(at: 1).width = controlsWidth
        grid.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16)
        ])

        return content
    }

    private func makeVideoTabView(width: CGFloat) -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 500))

        let controlsWidth: CGFloat = 300
        let labelsWidth: CGFloat = 250

        videoStartStopField.translatesAutoresizingMaskIntoConstraints = false
        videoPauseResumeField.translatesAutoresizingMaskIntoConstraints = false
        videoFileFormatPopup.translatesAutoresizingMaskIntoConstraints = false
        videoCodecPopup.translatesAutoresizingMaskIntoConstraints = false
        videoFrameRatePopup.translatesAutoresizingMaskIntoConstraints = false
        videoQualityPopup.translatesAutoresizingMaskIntoConstraints = false
        videoStartDelayPopup.translatesAutoresizingMaskIntoConstraints = false
        videoAudioPopup.translatesAutoresizingMaskIntoConstraints = false

        videoStartStopField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoPauseResumeField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoFileFormatPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoCodecPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoFrameRatePopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoQualityPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoStartDelayPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoAudioPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true

        let showCursorContainer = makeSwitchContainer(videoShowCursorSwitch, width: controlsWidth)
        let autoOpenContainer = makeSwitchContainer(autoOpenVideoSwitch, width: controlsWidth)
        let videosFolderControl = makeFolderControl(pathField: videosPathField, button: chooseVideosButton, width: controlsWidth)

        let grid = NSGridView(views: [
            [videoStartStopLabel, videoStartStopField],
            [videoPauseResumeLabel, videoPauseResumeField],
            [videoFileFormatLabel, videoFileFormatPopup],
            [videoCodecLabel, videoCodecPopup],
            [videoFrameRateLabel, videoFrameRatePopup],
            [videoQualityLabel, videoQualityPopup],
            [videoStartDelayLabel, videoStartDelayPopup],
            [videoAudioLabel, videoAudioPopup],
            [videoShowCursorLabel, showCursorContainer],
            [autoOpenVideoLabel, autoOpenContainer],
            [videosFolderLabel, videosFolderControl]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 14
        grid.column(at: 0).width = labelsWidth
        grid.column(at: 1).width = controlsWidth
        grid.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16)
        ])

        return content
    }

    private func makeSwitchContainer(_ toggle: NSSwitch, width: CGFloat) -> NSView {
        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.heightAnchor.constraint(equalToConstant: 26).isActive = true

        toggle.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toggle)
        NSLayoutConstraint.activate([
            toggle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func makeFolderControl(pathField: NSTextField, button: NSButton, width: CGFloat) -> NSView {
        pathField.isBezeled = true
        pathField.isEditable = false
        pathField.isSelectable = true
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.font = NSFont.systemFont(ofSize: 12)
        pathField.translatesAutoresizingMaskIntoConstraints = false

        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [pathField, button])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        pathField.widthAnchor.constraint(equalToConstant: width - 90).isActive = true
        button.widthAnchor.constraint(equalToConstant: 78).isActive = true

        let container = NSView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.widthAnchor.constraint(equalToConstant: width).isActive = true
        container.heightAnchor.constraint(equalToConstant: 28).isActive = true

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func bindActions() {
        areaField.onAttemptChange = { [weak self] hotkey in
            self?.onAreaHotkeyChanged?(hotkey) ?? false
        }
        fullField.onAttemptChange = { [weak self] hotkey in
            self?.onFullHotkeyChanged?(hotkey) ?? false
        }
        videoStartStopField.onAttemptChange = { [weak self] hotkey in
            self?.onVideoHotkeyChanged?(hotkey) ?? false
        }
        videoPauseResumeField.onAttemptChange = { [weak self] hotkey in
            self?.onVideoPauseResumeHotkeyChanged?(hotkey) ?? false
        }

        languagePopup.target = self
        languagePopup.action = #selector(languagePopupChanged)

        screenshotActionPopup.target = self
        screenshotActionPopup.action = #selector(screenshotActionPopupChanged)

        screenshotFormatPopup.target = self
        screenshotFormatPopup.action = #selector(screenshotFormatPopupChanged)

        muteSoundSwitch.target = self
        muteSoundSwitch.action = #selector(muteSoundSwitchChanged)

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginSwitchChanged)

        videoFileFormatPopup.target = self
        videoFileFormatPopup.action = #selector(videoFileFormatPopupChanged)

        videoCodecPopup.target = self
        videoCodecPopup.action = #selector(videoCodecPopupChanged)

        videoFrameRatePopup.target = self
        videoFrameRatePopup.action = #selector(videoFrameRatePopupChanged)

        videoQualityPopup.target = self
        videoQualityPopup.action = #selector(videoQualityPopupChanged)

        videoStartDelayPopup.target = self
        videoStartDelayPopup.action = #selector(videoStartDelayPopupChanged)

        videoAudioPopup.target = self
        videoAudioPopup.action = #selector(videoAudioPopupChanged)

        videoShowCursorSwitch.target = self
        videoShowCursorSwitch.action = #selector(videoShowCursorSwitchChanged)

        autoOpenVideoSwitch.target = self
        autoOpenVideoSwitch.action = #selector(autoOpenVideoSwitchChanged)

        chooseScreenshotsButton.target = self
        chooseScreenshotsButton.action = #selector(chooseScreenshotsDirectory)

        chooseVideosButton.target = self
        chooseVideosButton.action = #selector(chooseVideosDirectory)

        donateButton.target = self
        donateButton.action = #selector(openDonateLink)
    }

    private func rebuildLanguagePopupTitles() {
        let selected = languageOptions[safe: languagePopup.indexOfSelectedItem] ?? AppSettings.shared.language
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: languageOptions.map(\.nativeName))
        if let index = languageOptions.firstIndex(of: selected) {
            languagePopup.selectItem(at: index)
        }
    }

    private func rebuildScreenshotActionPopupTitles() {
        let selected = screenshotActionOptions[safe: screenshotActionPopup.indexOfSelectedItem] ?? AppSettings.shared.screenshotAction
        screenshotActionPopup.removeAllItems()
        screenshotActionPopup.addItems(withTitles: screenshotActionOptions.map(\.title))
        if let index = screenshotActionOptions.firstIndex(of: selected) {
            screenshotActionPopup.selectItem(at: index)
        }
    }

    private func rebuildScreenshotFormatPopupTitles() {
        let selected = screenshotFormatOptions[safe: screenshotFormatPopup.indexOfSelectedItem] ?? AppSettings.shared.screenshotFileFormat
        screenshotFormatPopup.removeAllItems()
        screenshotFormatPopup.addItems(withTitles: screenshotFormatOptions.map(\.title))
        if let index = screenshotFormatOptions.firstIndex(of: selected) {
            screenshotFormatPopup.selectItem(at: index)
        }
    }

    private func rebuildVideoFileFormatPopupTitles() {
        let selected = videoFileFormatOptions[safe: videoFileFormatPopup.indexOfSelectedItem] ?? AppSettings.shared.videoFileFormat
        videoFileFormatPopup.removeAllItems()
        videoFileFormatPopup.addItems(withTitles: videoFileFormatOptions.map(\.title))
        if let index = videoFileFormatOptions.firstIndex(of: selected) {
            videoFileFormatPopup.selectItem(at: index)
        }
    }

    private func rebuildVideoCodecPopupTitles() {
        let selected = videoCodecOptions[safe: videoCodecPopup.indexOfSelectedItem] ?? AppSettings.shared.videoCodec
        videoCodecPopup.removeAllItems()
        videoCodecPopup.addItems(withTitles: videoCodecOptions.map(\.title))
        if let index = videoCodecOptions.firstIndex(of: selected) {
            videoCodecPopup.selectItem(at: index)
        }
    }

    private func rebuildVideoFrameRatePopupTitles() {
        let selected = videoFrameRateOptions[safe: videoFrameRatePopup.indexOfSelectedItem] ?? AppSettings.shared.videoFrameRate
        videoFrameRatePopup.removeAllItems()
        videoFrameRatePopup.addItems(withTitles: videoFrameRateOptions.map(\.title))
        if let index = videoFrameRateOptions.firstIndex(of: selected) {
            videoFrameRatePopup.selectItem(at: index)
        }
    }

    private func rebuildVideoQualityPopupTitles() {
        let selected = videoQualityOptions[safe: videoQualityPopup.indexOfSelectedItem] ?? AppSettings.shared.videoQualityPreset
        videoQualityPopup.removeAllItems()
        videoQualityPopup.addItems(withTitles: videoQualityOptions.map(\.title))
        if let index = videoQualityOptions.firstIndex(of: selected) {
            videoQualityPopup.selectItem(at: index)
        }
    }

    private func rebuildVideoStartDelayPopupTitles() {
        let selected = videoStartDelayOptions[safe: videoStartDelayPopup.indexOfSelectedItem]
            ?? VideoStartDelayOption(rawValue: AppSettings.shared.videoStartDelaySeconds)
            ?? .off
        videoStartDelayPopup.removeAllItems()
        videoStartDelayPopup.addItems(withTitles: videoStartDelayOptions.map(\.title))
        if let index = videoStartDelayOptions.firstIndex(of: selected) {
            videoStartDelayPopup.selectItem(at: index)
        }
    }

    private func rebuildVideoAudioPopupTitles() {
        let selected = videoAudioOptions[safe: videoAudioPopup.indexOfSelectedItem] ?? AppSettings.shared.videoAudioMode
        videoAudioPopup.removeAllItems()
        videoAudioPopup.addItems(withTitles: videoAudioOptions.map(\.title))
        if let index = videoAudioOptions.firstIndex(of: selected) {
            videoAudioPopup.selectItem(at: index)
        }
    }

    @objc
    private func languagePopupChanged() {
        guard languagePopup.indexOfSelectedItem >= 0, languagePopup.indexOfSelectedItem < languageOptions.count else {
            return
        }
        onLanguageChanged?(languageOptions[languagePopup.indexOfSelectedItem])
    }

    @objc
    private func screenshotActionPopupChanged() {
        guard screenshotActionPopup.indexOfSelectedItem >= 0, screenshotActionPopup.indexOfSelectedItem < screenshotActionOptions.count else {
            return
        }
        onScreenshotActionChanged?(screenshotActionOptions[screenshotActionPopup.indexOfSelectedItem])
    }

    @objc
    private func screenshotFormatPopupChanged() {
        guard screenshotFormatPopup.indexOfSelectedItem >= 0, screenshotFormatPopup.indexOfSelectedItem < screenshotFormatOptions.count else {
            return
        }
        onScreenshotFormatChanged?(screenshotFormatOptions[screenshotFormatPopup.indexOfSelectedItem])
    }

    @objc
    private func muteSoundSwitchChanged() {
        onMuteScreenshotSoundChanged?(muteSoundSwitch.state == .on)
    }

    @objc
    private func launchAtLoginSwitchChanged() {
        onLaunchAtLoginChanged?(launchAtLoginSwitch.state == .on)
    }

    @objc
    private func videoFileFormatPopupChanged() {
        guard videoFileFormatPopup.indexOfSelectedItem >= 0, videoFileFormatPopup.indexOfSelectedItem < videoFileFormatOptions.count else {
            return
        }
        onVideoFileFormatChanged?(videoFileFormatOptions[videoFileFormatPopup.indexOfSelectedItem])
    }

    @objc
    private func videoCodecPopupChanged() {
        guard videoCodecPopup.indexOfSelectedItem >= 0, videoCodecPopup.indexOfSelectedItem < videoCodecOptions.count else {
            return
        }
        onVideoCodecChanged?(videoCodecOptions[videoCodecPopup.indexOfSelectedItem])
    }

    @objc
    private func videoFrameRatePopupChanged() {
        guard videoFrameRatePopup.indexOfSelectedItem >= 0, videoFrameRatePopup.indexOfSelectedItem < videoFrameRateOptions.count else {
            return
        }
        onVideoFrameRateChanged?(videoFrameRateOptions[videoFrameRatePopup.indexOfSelectedItem])
    }

    @objc
    private func videoQualityPopupChanged() {
        guard videoQualityPopup.indexOfSelectedItem >= 0, videoQualityPopup.indexOfSelectedItem < videoQualityOptions.count else {
            return
        }
        onVideoQualityPresetChanged?(videoQualityOptions[videoQualityPopup.indexOfSelectedItem])
    }

    @objc
    private func videoStartDelayPopupChanged() {
        guard videoStartDelayPopup.indexOfSelectedItem >= 0, videoStartDelayPopup.indexOfSelectedItem < videoStartDelayOptions.count else {
            return
        }
        onVideoStartDelayChanged?(videoStartDelayOptions[videoStartDelayPopup.indexOfSelectedItem])
    }

    @objc
    private func videoAudioPopupChanged() {
        guard videoAudioPopup.indexOfSelectedItem >= 0, videoAudioPopup.indexOfSelectedItem < videoAudioOptions.count else {
            return
        }
        onVideoAudioModeChanged?(videoAudioOptions[videoAudioPopup.indexOfSelectedItem])
    }

    @objc
    private func videoShowCursorSwitchChanged() {
        onVideoShowCursorChanged?(videoShowCursorSwitch.state == .on)
    }

    @objc
    private func autoOpenVideoSwitchChanged() {
        onAutoOpenRecordedVideoChanged?(autoOpenVideoSwitch.state == .on)
    }

    @objc
    private func chooseScreenshotsDirectory() {
        onChooseScreenshotsDirectory?()
    }

    @objc
    private func chooseVideosDirectory() {
        onChooseVideosDirectory?()
    }

    @objc
    private func openDonateLink() {
        guard let url = URL(string: "https://www.donationalerts.com/r/medusa411") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else {
            return nil
        }
        return self[index]
    }
}
