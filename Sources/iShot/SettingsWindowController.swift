import AppKit
import Foundation

@MainActor
final class SettingsWindowController: NSWindowController {
    var onAreaHotkeyChanged: ((Hotkey) -> Bool)?
    var onFullHotkeyChanged: ((Hotkey) -> Bool)?
    var onVideoHotkeyChanged: ((Hotkey) -> Bool)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onScreenshotActionChanged: ((ScreenshotAction) -> Void)?
    var onMuteScreenshotSoundChanged: ((Bool) -> Void)?
    var onVideoAudioModeChanged: ((AudioCaptureMode) -> Void)?
    var onChooseScreenshotsDirectory: (() -> Void)?
    var onChooseVideosDirectory: (() -> Void)?

    private let hotkeysTitleLabel = NSTextField(labelWithString: "")
    private let areaLabel = NSTextField(labelWithString: "")
    private let fullLabel = NSTextField(labelWithString: "")
    private let videoLabel = NSTextField(labelWithString: "")

    private let languageLabel = NSTextField(labelWithString: "")
    private let screenshotActionLabel = NSTextField(labelWithString: "")
    private let muteSoundLabel = NSTextField(labelWithString: "")
    private let videoAudioLabel = NSTextField(labelWithString: "")
    private let screenshotsFolderLabel = NSTextField(labelWithString: "")
    private let videosFolderLabel = NSTextField(labelWithString: "")

    private let footerLabel = NSTextField(labelWithString: "")
    private let donateButton = NSButton(title: "", target: nil, action: nil)

    private let areaField: HotkeyRecorderField
    private let fullField: HotkeyRecorderField
    private let videoField: HotkeyRecorderField

    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let screenshotActionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let muteSoundSwitch = NSSwitch(frame: .zero)
    private let videoAudioPopup = NSPopUpButton(frame: .zero, pullsDown: false)

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
    private let audioOptions: [AudioCaptureMode] = [.system, .silent]

    init(settings: AppSettings) {
        areaField = HotkeyRecorderField(hotkey: settings.hotkeys.areaCapture)
        fullField = HotkeyRecorderField(hotkey: settings.hotkeys.fullCapture)
        videoField = HotkeyRecorderField(hotkey: settings.hotkeys.videoToggle)

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
        videoField.hotkey = settings.hotkeys.videoToggle

        muteSoundSwitch.state = settings.muteScreenshotSound ? .on : .off

        if let languageIndex = languageOptions.firstIndex(of: settings.language) {
            languagePopup.selectItem(at: languageIndex)
        }
        if let actionIndex = screenshotActionOptions.firstIndex(of: settings.screenshotAction) {
            screenshotActionPopup.selectItem(at: actionIndex)
        }
        if let audioIndex = audioOptions.firstIndex(of: settings.videoAudioMode) {
            videoAudioPopup.selectItem(at: audioIndex)
        }

        screenshotsPathField.stringValue = settings.screenshotsDirectory.path
        videosPathField.stringValue = settings.videosDirectory.path
    }

    func refreshLocalization() {
        window?.title = Localizer.text("Настройки Cliptara", "Cliptara Settings")

        hotkeysTitleLabel.stringValue = Localizer.text("Горячие клавиши", "Hotkeys")
        areaLabel.stringValue = Localizer.text("Скриншот области:", "Area screenshot:")
        fullLabel.stringValue = Localizer.text("Скриншот экрана:", "Screen screenshot:")
        videoLabel.stringValue = Localizer.text("Старт/стоп видеозаписи:", "Video start/stop:")

        languageLabel.stringValue = Localizer.text("Язык:", "Language:")
        screenshotActionLabel.stringValue = Localizer.text("Действия со скриншотами:", "Screenshot action:")
        muteSoundLabel.stringValue = Localizer.text("Выключить звук скриншота:", "Mute screenshot sound:")
        videoAudioLabel.stringValue = Localizer.text("Звук видео:", "Video audio:")
        screenshotsFolderLabel.stringValue = Localizer.text("Папка скриншотов:", "Screenshots folder:")
        videosFolderLabel.stringValue = Localizer.text("Папка видео:", "Videos folder:")

        chooseScreenshotsButton.title = Localizer.text("Выбрать", "Choose")
        chooseVideosButton.title = Localizer.text("Выбрать", "Choose")

        donateButton.title = Localizer.text("Донат", "Donate")
        footerLabel.stringValue = "Created by medusa411"

        rebuildLanguagePopupTitles()
        rebuildScreenshotActionPopupTitles()
        rebuildAudioPopupTitles()

        reloadFromSettings()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 520),
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

        hotkeysTitleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        rootStack.addArrangedSubview(hotkeysTitleLabel)

        let controlsWidth: CGFloat = 260
        let labelsWidth: CGFloat = 220
        let fullWidth: CGFloat = 620

        areaField.translatesAutoresizingMaskIntoConstraints = false
        fullField.translatesAutoresizingMaskIntoConstraints = false
        videoField.translatesAutoresizingMaskIntoConstraints = false
        languagePopup.translatesAutoresizingMaskIntoConstraints = false
        screenshotActionPopup.translatesAutoresizingMaskIntoConstraints = false
        videoAudioPopup.translatesAutoresizingMaskIntoConstraints = false

        areaField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        fullField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoField.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        languagePopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        screenshotActionPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        videoAudioPopup.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true

        let hotkeysGrid = NSGridView(views: [
            [areaLabel, areaField],
            [fullLabel, fullField],
            [videoLabel, videoField]
        ])
        hotkeysGrid.rowSpacing = 10
        hotkeysGrid.columnSpacing = 14
        hotkeysGrid.column(at: 0).width = labelsWidth
        hotkeysGrid.column(at: 1).width = controlsWidth
        hotkeysGrid.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(hotkeysGrid)

        let separatorTop = NSBox()
        separatorTop.boxType = .separator
        separatorTop.translatesAutoresizingMaskIntoConstraints = false
        separatorTop.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        rootStack.addArrangedSubview(separatorTop)

        let muteContainer = NSView(frame: .zero)
        muteContainer.translatesAutoresizingMaskIntoConstraints = false
        muteContainer.widthAnchor.constraint(equalToConstant: controlsWidth).isActive = true
        muteContainer.heightAnchor.constraint(equalToConstant: 26).isActive = true

        muteSoundSwitch.translatesAutoresizingMaskIntoConstraints = false
        muteContainer.addSubview(muteSoundSwitch)
        NSLayoutConstraint.activate([
            muteSoundSwitch.leadingAnchor.constraint(equalTo: muteContainer.leadingAnchor),
            muteSoundSwitch.centerYAnchor.constraint(equalTo: muteContainer.centerYAnchor)
        ])

        let screenshotsFolderControl = makeFolderControl(pathField: screenshotsPathField, button: chooseScreenshotsButton, width: controlsWidth)
        let videosFolderControl = makeFolderControl(pathField: videosPathField, button: chooseVideosButton, width: controlsWidth)

        let optionsGrid = NSGridView(views: [
            [languageLabel, languagePopup],
            [screenshotActionLabel, screenshotActionPopup],
            [muteSoundLabel, muteContainer],
            [videoAudioLabel, videoAudioPopup],
            [screenshotsFolderLabel, screenshotsFolderControl],
            [videosFolderLabel, videosFolderControl]
        ])
        optionsGrid.rowSpacing = 10
        optionsGrid.columnSpacing = 14
        optionsGrid.column(at: 0).width = labelsWidth
        optionsGrid.column(at: 1).width = controlsWidth
        optionsGrid.translatesAutoresizingMaskIntoConstraints = false

        rootStack.addArrangedSubview(optionsGrid)

        let separatorBottom = NSBox()
        separatorBottom.boxType = .separator
        separatorBottom.translatesAutoresizingMaskIntoConstraints = false
        separatorBottom.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        rootStack.addArrangedSubview(separatorBottom)

        donateButton.bezelStyle = .rounded
        donateButton.translatesAutoresizingMaskIntoConstraints = false
        donateButton.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let donateContainer = NSView(frame: .zero)
        donateContainer.translatesAutoresizingMaskIntoConstraints = false
        donateContainer.heightAnchor.constraint(equalToConstant: 30).isActive = true
        donateContainer.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
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
        footerContainer.widthAnchor.constraint(equalToConstant: fullWidth).isActive = true
        footerContainer.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerLabel.centerXAnchor.constraint(equalTo: footerContainer.centerXAnchor),
            footerLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor)
        ])
        rootStack.addArrangedSubview(footerContainer)
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

        videoField.onAttemptChange = { [weak self] hotkey in
            self?.onVideoHotkeyChanged?(hotkey) ?? false
        }

        languagePopup.target = self
        languagePopup.action = #selector(languagePopupChanged)

        screenshotActionPopup.target = self
        screenshotActionPopup.action = #selector(screenshotActionPopupChanged)

        muteSoundSwitch.target = self
        muteSoundSwitch.action = #selector(muteSoundSwitchChanged)

        videoAudioPopup.target = self
        videoAudioPopup.action = #selector(videoAudioPopupChanged)

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
        languagePopup.addItems(withTitles: languageOptions.map { $0.nativeName })

        if let index = languageOptions.firstIndex(of: selected) {
            languagePopup.selectItem(at: index)
        }
    }

    private func rebuildScreenshotActionPopupTitles() {
        let selected = screenshotActionOptions[safe: screenshotActionPopup.indexOfSelectedItem] ?? AppSettings.shared.screenshotAction

        screenshotActionPopup.removeAllItems()
        screenshotActionPopup.addItems(withTitles: screenshotActionOptions.map { $0.title })

        if let index = screenshotActionOptions.firstIndex(of: selected) {
            screenshotActionPopup.selectItem(at: index)
        }
    }

    private func rebuildAudioPopupTitles() {
        let selected = audioOptions[safe: videoAudioPopup.indexOfSelectedItem] ?? AppSettings.shared.videoAudioMode

        videoAudioPopup.removeAllItems()
        videoAudioPopup.addItems(withTitles: audioOptions.map { $0.title })

        if let index = audioOptions.firstIndex(of: selected) {
            videoAudioPopup.selectItem(at: index)
        }
    }

    @objc
    private func languagePopupChanged() {
        guard languagePopup.indexOfSelectedItem >= 0,
              languagePopup.indexOfSelectedItem < languageOptions.count else {
            return
        }
        onLanguageChanged?(languageOptions[languagePopup.indexOfSelectedItem])
    }

    @objc
    private func screenshotActionPopupChanged() {
        guard screenshotActionPopup.indexOfSelectedItem >= 0,
              screenshotActionPopup.indexOfSelectedItem < screenshotActionOptions.count else {
            return
        }
        onScreenshotActionChanged?(screenshotActionOptions[screenshotActionPopup.indexOfSelectedItem])
    }

    @objc
    private func muteSoundSwitchChanged() {
        onMuteScreenshotSoundChanged?(muteSoundSwitch.state == .on)
    }

    @objc
    private func videoAudioPopupChanged() {
        guard videoAudioPopup.indexOfSelectedItem >= 0,
              videoAudioPopup.indexOfSelectedItem < audioOptions.count else {
            return
        }
        onVideoAudioModeChanged?(audioOptions[videoAudioPopup.indexOfSelectedItem])
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
