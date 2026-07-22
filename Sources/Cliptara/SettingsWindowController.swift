import AppKit
import Foundation

private enum SettingsSection: String, CaseIterable {
    case general
    case screenshots
    case video
    case about

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .screenshots:
            return "camera.viewfinder"
        case .video:
            return "video"
        case .about:
            return "person.2"
        }
    }
}

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

    private let contentHost = NSView(frame: .zero)
    private var sidebarButtons: [SettingsSection: SettingsSidebarButton] = [:]
    private var pageViews: [SettingsSection: NSView] = [:]
    private var localizedLabels: [String: NSTextField] = [:]
    private var languageButtons: [AppLanguage: LanguageChoiceButton] = [:]
    private var selectedSection: SettingsSection = .general

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
    private let appVersionLabel = NSTextField(labelWithString: "")
    private let appVersionValueLabel = NSTextField(labelWithString: "")
    private let githubLinkButton = NSButton(title: "GitHub", target: nil, action: nil)
    private let donatLinkButton = NSButton(title: "Donat", target: nil, action: nil)

    private let areaField: HotkeyRecorderField
    private let fullField: HotkeyRecorderField
    private let videoStartStopField: HotkeyRecorderField
    private let videoPauseResumeField: HotkeyRecorderField

    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let muteSoundSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let launchAtLoginSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let videoFileFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoCodecPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoFrameRatePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoQualityPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoStartDelayPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoAudioPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let videoShowCursorSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let autoOpenVideoSwitch = NSButton(checkboxWithTitle: "", target: nil, action: nil)

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
    private let screenshotActionOptions: [ScreenshotAction] = [.copyToClipboard, .saveToFiles, .copyAndSave]
    private let screenshotFormatOptions: [ScreenshotFileFormat] = [.png, .jpg, .webp]
    private let videoAudioOptions: [AudioCaptureMode] = [.system, .silent]
    private let videoFileFormatOptions = VideoFileFormat.allCases
    private let videoCodecOptions = VideoCodecOption.allCases
    private let videoFrameRateOptions = VideoFrameRateOption.allCases
    private let videoQualityOptions = VideoQualityPreset.allCases
    private let videoStartDelayOptions = VideoStartDelayOption.allCases

    private let windowWidth: CGFloat = 980
    private let windowHeight: CGFloat = 700
    private let sidebarWidth: CGFloat = 212
    private let labelsWidth: CGFloat = 210
    private let controlsWidth: CGFloat = 330

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

    override func showWindow(_ sender: Any?) {
        guard let window else {
            return
        }

        let targetSize = NSSize(width: windowWidth, height: windowHeight)
        window.minSize = NSSize(width: 900, height: 620)
        window.setContentSize(targetSize)
        window.center()
        super.showWindow(sender)
        window.makeKeyAndOrderFront(sender)
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

        for (language, button) in languageButtons {
            button.isSelected = language == settings.language
        }
    }

    func refreshLocalization() {
        window?.title = Localizer.text("Настройки Cliptara", "Cliptara Settings")

        sidebarButtons[.general]?.updateTitle(Localizer.text("Основное", "General"))
        sidebarButtons[.screenshots]?.updateTitle(Localizer.text("Скриншоты", "Screenshots"))
        sidebarButtons[.video]?.updateTitle(Localizer.text("Видео", "Video"))
        sidebarButtons[.about]?.updateTitle(Localizer.text("О программе", "About"))

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
        appVersionLabel.stringValue = Localizer.text("Версия программы:", "App version:")
        appVersionValueLabel.stringValue = appVersionString()

        chooseScreenshotsButton.title = Localizer.text("Выбрать", "Choose")
        chooseVideosButton.title = Localizer.text("Выбрать", "Choose")
        launchAtLoginSwitch.title = Localizer.text("Автозапуск при входе", "Launch at login")
        muteSoundSwitch.title = Localizer.text("Выключить звук скриншота", "Mute screenshot sound")
        videoShowCursorSwitch.title = Localizer.text("Показывать курсор", "Show cursor")
        autoOpenVideoSwitch.title = Localizer.text("Открывать видео после записи", "Open video after recording")
        githubLinkButton.title = "GitHub"
        donatLinkButton.title = "Donat"
        configureLinkButton(githubLinkButton)
        configureLinkButton(donatLinkButton)

        setLocalizedLabel("sidebar.appName", to: "Cliptara")
        setLocalizedLabel("sidebar.subtitle", to: Localizer.text("Снимки и запись", "Capture & Recording"))

        setLocalizedLabel("page.general.title", to: Localizer.text("Основное", "General"))
        setLocalizedLabel("page.general.subtitle", to: Localizer.text(
            "Язык интерфейса и запуск приложения.",
            "Interface language and app startup."
        ))
        setLocalizedLabel("page.screenshots.title", to: Localizer.text("Скриншоты", "Screenshots"))
        setLocalizedLabel("page.screenshots.subtitle", to: Localizer.text(
            "Горячие клавиши, формат и сохранение снимков.",
            "Screenshot shortcuts, format and saving."
        ))
        setLocalizedLabel("page.video.title", to: Localizer.text("Видео", "Video"))
        setLocalizedLabel("page.video.subtitle", to: Localizer.text(
            "Качество записи, звук и место сохранения.",
            "Recording quality, audio and storage."
        ))
        setLocalizedLabel("page.about.title", to: Localizer.text("О программе", "About"))
        setLocalizedLabel("page.about.subtitle", to: Localizer.text(
            "Версия, ссылки и информация о создателе.",
            "Version, links and creator information."
        ))

        setLocalizedLabel("card.language", to: Localizer.text("Язык", "Language"))
        setLocalizedLabel("card.languageHint", to: Localizer.text(
            "Изменение языка применяется сразу и сохраняется автоматически.",
            "Language changes are applied immediately and saved automatically."
        ))
        setLocalizedLabel("card.startup", to: Localizer.text("Запуск", "Startup"))
        setLocalizedLabel("card.screenshots.hotkeys", to: Localizer.text("Горячие клавиши", "Hotkeys"))
        setLocalizedLabel("card.screenshots.capture", to: Localizer.text("Снимок", "Capture"))
        setLocalizedLabel("card.screenshots.storage", to: Localizer.text("Хранение", "Storage"))
        setLocalizedLabel("card.video.hotkeys", to: Localizer.text("Горячие клавиши", "Hotkeys"))
        setLocalizedLabel("card.video.recording", to: Localizer.text("Запись", "Recording"))
        setLocalizedLabel("card.video.behavior", to: Localizer.text("Поведение", "Behavior"))
        setLocalizedLabel("card.video.storage", to: Localizer.text("Хранение", "Storage"))
        setLocalizedLabel("about.creatorRole", to: Localizer.text("Создатель", "Creator"))
        setLocalizedLabel("about.description", to: Localizer.text(
            "Спасибо за использование Cliptara. Поддержка помогает быстрее улучшать интерфейс, стабильность и добавлять новые функции.",
            "Thank you for using Cliptara. Support helps improve the interface, stability, and new features faster."
        ))

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
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 900, height: 620)
        window.center()
        self.window = window

        guard let contentView = window.contentView else {
            return
        }

        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(sidebar)
        contentView.addSubview(contentHost)
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(greaterThanOrEqualToConstant: 900),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 620),

            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth),

            contentHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            contentHost.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentHost.topAnchor.constraint(equalTo: contentView.topAnchor),
            contentHost.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        buildPages()
        selectSection(.general)
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView(frame: .zero)
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active

        let iconView = NSImageView(frame: .zero)
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 38).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let appNameLabel = makeRegisteredLabel(key: "sidebar.appName", font: .systemFont(ofSize: 14, weight: .bold))
        let appSubtitleLabel = makeRegisteredLabel(key: "sidebar.subtitle", font: .systemFont(ofSize: 10, weight: .regular))
        appSubtitleLabel.textColor = .secondaryLabelColor
        appSubtitleLabel.lineBreakMode = .byWordWrapping
        appSubtitleLabel.maximumNumberOfLines = 2

        let appTextStack = NSStackView(views: [appNameLabel, appSubtitleLabel])
        appTextStack.orientation = .vertical
        appTextStack.alignment = .leading
        appTextStack.spacing = 0

        let appHeader = NSStackView(views: [iconView, appTextStack])
        appHeader.orientation = .horizontal
        appHeader.alignment = .centerY
        appHeader.spacing = 10
        appHeader.translatesAutoresizingMaskIntoConstraints = false

        let navigationStack = NSStackView()
        navigationStack.orientation = .vertical
        navigationStack.alignment = .leading
        navigationStack.spacing = 6
        navigationStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, section) in SettingsSection.allCases.enumerated() {
            let button = SettingsSidebarButton(
                title: "",
                symbolName: section.symbolName,
                target: self,
                action: #selector(sidebarButtonPressed(_:))
            )
            button.tag = index
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: sidebarWidth - 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
            sidebarButtons[section] = button
            navigationStack.addArrangedSubview(button)
        }

        let separator = NSBox(frame: .zero)
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        sidebar.addSubview(appHeader)
        sidebar.addSubview(navigationStack)
        sidebar.addSubview(separator)

        NSLayoutConstraint.activate([
            appHeader.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            appHeader.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -14),
            appHeader.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 58),

            navigationStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 14),
            navigationStack.topAnchor.constraint(equalTo: appHeader.bottomAnchor, constant: 24),

            separator.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: sidebar.topAnchor),
            separator.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1)
        ])

        return sidebar
    }

    private func buildPages() {
        prepareControlsForNewLayout()

        let pages: [(SettingsSection, NSView)] = [
            (.general, makeGeneralPage()),
            (.screenshots, makeScreenshotsPage()),
            (.video, makeVideoPage()),
            (.about, makeAboutPage())
        ]

        for (section, page) in pages {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = true
            contentHost.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                page.topAnchor.constraint(equalTo: contentHost.topAnchor),
                page.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor)
            ])
            pageViews[section] = page
        }
    }

    private func prepareControlsForNewLayout() {
        let popupButtons = [
            screenshotActionPopup,
            screenshotFormatPopup,
            videoFileFormatPopup,
            videoCodecPopup,
            videoFrameRatePopup,
            videoQualityPopup,
            videoStartDelayPopup,
            videoAudioPopup
        ]

        for popup in popupButtons {
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        }

        areaField.translatesAutoresizingMaskIntoConstraints = false
        fullField.translatesAutoresizingMaskIntoConstraints = false
        videoStartStopField.translatesAutoresizingMaskIntoConstraints = false
        videoPauseResumeField.translatesAutoresizingMaskIntoConstraints = false
        areaField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        fullField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoStartStopField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoPauseResumeField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true

        for checkbox in [muteSoundSwitch, launchAtLoginSwitch, videoShowCursorSwitch, autoOpenVideoSwitch] {
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkbox.font = .systemFont(ofSize: 13, weight: .medium)
        }
    }

    private func makeGeneralPage() -> NSView {
        let languageCard = makeCard(
            titleKey: "card.language",
            content: makeLanguageSelector()
        )

        let startupStack = makeVerticalStack([launchAtLoginSwitch], spacing: 8)
        let startupCard = makeCard(titleKey: "card.startup", content: startupStack)

        return makePage(
            titleKey: "page.general.title",
            subtitleKey: "page.general.subtitle",
            cards: [languageCard, startupCard]
        )
    }

    private func makeScreenshotsPage() -> NSView {
        let hotkeysGrid = makeFormGrid(rows: [
            [areaLabel, areaField],
            [fullLabel, fullField]
        ])
        let hotkeysCard = makeCard(titleKey: "card.screenshots.hotkeys", content: hotkeysGrid)

        let captureGrid = makeFormGrid(rows: [
            [screenshotActionLabel, screenshotActionPopup],
            [screenshotFormatLabel, screenshotFormatPopup]
        ])
        let captureContent = makeVerticalStack([captureGrid, muteSoundSwitch], spacing: 14)
        let captureCard = makeCard(titleKey: "card.screenshots.capture", content: captureContent)

        let folderControl = makeFolderControl(
            pathField: screenshotsPathField,
            button: chooseScreenshotsButton,
            width: controlsWidth
        )
        let storageGrid = makeFormGrid(rows: [[screenshotsFolderLabel, folderControl]])
        let storageCard = makeCard(titleKey: "card.screenshots.storage", content: storageGrid)

        return makePage(
            titleKey: "page.screenshots.title",
            subtitleKey: "page.screenshots.subtitle",
            cards: [hotkeysCard, captureCard, storageCard]
        )
    }

    private func makeVideoPage() -> NSView {
        let hotkeysGrid = makeFormGrid(rows: [
            [videoStartStopLabel, videoStartStopField],
            [videoPauseResumeLabel, videoPauseResumeField]
        ])
        let hotkeysCard = makeCard(titleKey: "card.video.hotkeys", content: hotkeysGrid)

        let recordingGrid = makeFormGrid(rows: [
            [videoFileFormatLabel, videoFileFormatPopup],
            [videoCodecLabel, videoCodecPopup],
            [videoFrameRateLabel, videoFrameRatePopup],
            [videoQualityLabel, videoQualityPopup],
            [videoStartDelayLabel, videoStartDelayPopup],
            [videoAudioLabel, videoAudioPopup]
        ])
        let recordingCard = makeCard(titleKey: "card.video.recording", content: recordingGrid)

        let behaviorStack = makeVerticalStack(
            [videoShowCursorSwitch, autoOpenVideoSwitch],
            spacing: 10
        )
        let behaviorCard = makeCard(titleKey: "card.video.behavior", content: behaviorStack)

        let folderControl = makeFolderControl(
            pathField: videosPathField,
            button: chooseVideosButton,
            width: controlsWidth
        )
        let storageGrid = makeFormGrid(rows: [[videosFolderLabel, folderControl]])
        let storageCard = makeCard(titleKey: "card.video.storage", content: storageGrid)

        return makePage(
            titleKey: "page.video.title",
            subtitleKey: "page.video.subtitle",
            cards: [hotkeysCard, recordingCard, behaviorCard, storageCard]
        )
    }

    private func makeAboutPage() -> NSView {
        let creatorIcon = NSImageView(frame: .zero)
        creatorIcon.image = NSApp.applicationIconImage
        creatorIcon.imageScaling = .scaleProportionallyUpOrDown
        creatorIcon.translatesAutoresizingMaskIntoConstraints = false
        creatorIcon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        creatorIcon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let roleLabel = makeRegisteredLabel(
            key: "about.creatorRole",
            font: .systemFont(ofSize: 12, weight: .semibold)
        )
        roleLabel.textColor = .secondaryLabelColor

        let creatorNameLabel = NSTextField(labelWithString: "medusa411")
        creatorNameLabel.font = .systemFont(ofSize: 24, weight: .bold)

        let descriptionLabel = makeRegisteredLabel(
            key: "about.description",
            font: .systemFont(ofSize: 12, weight: .regular)
        )
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 3
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        appVersionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        appVersionValueLabel.font = .systemFont(ofSize: 12, weight: .regular)
        appVersionLabel.textColor = .secondaryLabelColor
        appVersionValueLabel.textColor = .secondaryLabelColor
        let versionRow = NSStackView(views: [appVersionLabel, appVersionValueLabel])
        versionRow.orientation = .horizontal
        versionRow.alignment = .firstBaseline
        versionRow.spacing = 6

        let creatorText = NSStackView(views: [roleLabel, creatorNameLabel, descriptionLabel, versionRow])
        creatorText.orientation = .vertical
        creatorText.alignment = .leading
        creatorText.spacing = 5
        creatorText.setHuggingPriority(.defaultLow, for: .horizontal)

        configureLinkButton(githubLinkButton)
        configureLinkButton(donatLinkButton)
        githubLinkButton.widthAnchor.constraint(equalToConstant: 112).isActive = true
        donatLinkButton.widthAnchor.constraint(equalToConstant: 112).isActive = true

        let actionStack = NSStackView(views: [githubLinkButton, donatLinkButton])
        actionStack.orientation = .vertical
        actionStack.alignment = .centerX
        actionStack.spacing = 8

        let creatorContent = NSStackView(views: [creatorIcon, creatorText, actionStack])
        creatorContent.orientation = .horizontal
        creatorContent.alignment = .centerY
        creatorContent.spacing = 16

        let creatorCard = makeCard(titleKey: nil, content: creatorContent, highlighted: true)
        return makePage(
            titleKey: "page.about.title",
            subtitleKey: "page.about.subtitle",
            cards: [creatorCard]
        )
    }

    private func makeLanguageSelector() -> NSView {
        languageButtons.removeAll()

        let languageRows = languageOptions.chunked(into: 4).map { languages in
            languages.map { language -> NSView in
                let button = LanguageChoiceButton(
                    language: language,
                    code: languageCode(for: language),
                    target: self,
                    action: #selector(languageChoicePressed(_:))
                )
                button.translatesAutoresizingMaskIntoConstraints = false
                button.widthAnchor.constraint(equalToConstant: 126).isActive = true
                button.heightAnchor.constraint(equalToConstant: 54).isActive = true
                languageButtons[language] = button
                return button
            }
        }

        let grid = NSGridView(views: languageRows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = makeRegisteredLabel(
            key: "card.languageHint",
            font: .systemFont(ofSize: 11, weight: .regular)
        )
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2

        return makeVerticalStack([grid, hintLabel], spacing: 10)
    }

    private func makePage(titleKey: String, subtitleKey: String, cards: [NSView]) -> NSView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = FlippedContentView(frame: .zero)
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeRegisteredLabel(
            key: titleKey,
            font: .systemFont(ofSize: 30, weight: .bold)
        )
        let subtitleLabel = makeRegisteredLabel(
            key: subtitleKey,
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2

        let pageStack = NSStackView()
        pageStack.orientation = .vertical
        pageStack.alignment = .leading
        pageStack.spacing = 14
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        pageStack.addArrangedSubview(titleLabel)
        pageStack.setCustomSpacing(8, after: titleLabel)
        pageStack.addArrangedSubview(subtitleLabel)
        pageStack.setCustomSpacing(22, after: subtitleLabel)

        for card in cards {
            pageStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true
        }

        titleLabel.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true
        subtitleLabel.widthAnchor.constraint(equalTo: pageStack.widthAnchor).isActive = true

        documentView.addSubview(pageStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            pageStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 34),
            pageStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -34),
            pageStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 76),
            pageStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -32)
        ])

        return scrollView
    }

    private func makeCard(titleKey: String?, content: NSView, highlighted: Bool = false) -> NSView {
        let card = SettingsCardView(highlighted: highlighted)
        card.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let titleKey {
            let titleLabel = makeRegisteredLabel(
                key: titleKey,
                font: .systemFont(ofSize: 13, weight: .semibold)
            )
            stack.addArrangedSubview(titleLabel)
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        content.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(content)
        content.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }

    private func makeFormGrid(rows: [[NSView]]) -> NSGridView {
        for row in rows {
            guard row.count >= 2 else { continue }
            if let label = row[0] as? NSTextField {
                label.font = .systemFont(ofSize: 13, weight: .medium)
                label.lineBreakMode = .byWordWrapping
                label.maximumNumberOfLines = 2
            }
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 10
        grid.columnSpacing = 16
        grid.column(at: 0).width = labelsWidth
        grid.column(at: 1).width = controlsWidth
        grid.translatesAutoresizingMaskIntoConstraints = false
        return grid
    }

    private func makeVerticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeRegisteredLabel(key: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.translatesAutoresizingMaskIntoConstraints = false
        localizedLabels[key] = label
        return label
    }

    private func setLocalizedLabel(_ key: String, to value: String) {
        localizedLabels[key]?.stringValue = value
    }

    private func languageCode(for language: AppLanguage) -> String {
        switch language {
        case .russian: return "RU"
        case .english: return "EN"
        case .german: return "DE"
        case .french: return "FR"
        case .spanish: return "ES"
        case .chineseSimplified: return "简"
        case .chineseTraditional: return "繁"
        case .arabic: return "AR"
        }
    }

    private func selectSection(_ section: SettingsSection) {
        selectedSection = section
        for (candidate, page) in pageViews {
            page.isHidden = candidate != section
        }
        for (candidate, button) in sidebarButtons {
            button.isSelected = candidate == section
        }
    }

    @objc
    private func sidebarButtonPressed(_ sender: NSButton) {
        guard SettingsSection.allCases.indices.contains(sender.tag) else { return }
        selectSection(SettingsSection.allCases[sender.tag])
    }

    @objc
    private func languageChoicePressed(_ sender: LanguageChoiceButton) {
        guard let index = languageOptions.firstIndex(of: sender.language) else { return }
        languagePopup.selectItem(at: index)
        onLanguageChanged?(sender.language)
    }

    private func configureLinkButton(_ button: NSButton) {
        button.isBordered = true
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        guard !build.isEmpty, build != "0", build != version else {
            return version
        }
        return "\(version) (\(build))"
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

        githubLinkButton.target = self
        githubLinkButton.action = #selector(openGitHubLink)

        donatLinkButton.target = self
        donatLinkButton.action = #selector(openDonatLink)
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
    private func openGitHubLink() {
        guard let url = URL(string: "https://github.com/medusa4111/Cliptara") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func openDonatLink() {
        guard let url = URL(string: "https://www.donationalerts.com/r/medusa411") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
private final class SettingsSidebarButton: NSButton {
    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    init(title: String, symbolName: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        self.title = title
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        imagePosition = .imageLeading
        imageHugsTitle = true
        alignment = .left
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func updateTitle(_ value: String) {
        title = value
        setAccessibilityLabel(value)
        updateAppearance()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        let background = isSelected
            ? NSColor.systemBlue.withAlphaComponent(0.18)
            : NSColor.clear
        layer?.backgroundColor = background.cgColor
    }

    private func updateAppearance() {
        let color = isSelected ? NSColor.systemBlue : NSColor.secondaryLabelColor
        contentTintColor = color
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: color
            ]
        )
        needsDisplay = true
    }
}

@MainActor
private final class LanguageChoiceButton: NSButton {
    let language: AppLanguage

    var isSelected = false {
        didSet {
            updateAppearance()
        }
    }

    private let languageCode: String

    init(language: AppLanguage, code: String, target: AnyObject?, action: Selector?) {
        self.language = language
        self.languageCode = code
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        cell?.wraps = true
        cell?.lineBreakMode = .byWordWrapping
        setAccessibilityLabel(language.nativeName)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = (
            isSelected
                ? NSColor.systemBlue.withAlphaComponent(0.18)
                : NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        ).cgColor
        layer?.borderColor = (
            isSelected
                ? NSColor.systemBlue.withAlphaComponent(0.8)
                : NSColor.separatorColor.withAlphaComponent(0.9)
        ).cgColor
    }

    private func updateAppearance() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 1

        let title = NSMutableAttributedString(
            string: language.nativeName,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        title.append(NSAttributedString(
            string: "\n\(languageCode)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: isSelected ? NSColor.systemBlue : NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        ))
        attributedTitle = title
        needsDisplay = true
    }
}

@MainActor
private final class SettingsCardView: NSView {
    private let highlighted: Bool

    init(highlighted: Bool) {
        self.highlighted = highlighted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        super.updateLayer()
        if highlighted {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.42).cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.38).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.9).cgColor
        }
    }
}

@MainActor
private final class FlippedContentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else {
            return nil
        }
        return self[index]
    }

    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
