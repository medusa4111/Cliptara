import AppKit
import Foundation

@MainActor
final class VideoCompressionWindowController: NSWindowController, NSTextFieldDelegate {
    private enum DestinationMode: Int {
        case videosFolder = 0
        case customFolder = 1
    }

    private let settings: AppSettings
    private let compressor = VideoCompressor()

    private let titleLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let sourcePathField = NSTextField(labelWithString: "")
    private let chooseSourceButton = NSButton(title: "", target: nil, action: nil)

    private let targetLabel = NSTextField(labelWithString: "")
    private let targetSizeField = NSTextField(string: "20")
    private let targetSuffixLabel = NSTextField(labelWithString: "MB")

    private let destinationModeLabel = NSTextField(labelWithString: "")
    private let destinationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let destinationPathField = NSTextField(labelWithString: "")
    private let chooseDestinationButton = NSButton(title: "", target: nil, action: nil)

    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator(frame: .zero)
    private let compressButton = NSButton(title: "", target: nil, action: nil)

    private var sourceURL: URL?
    private var customDestinationDirectory: URL?

    init(settings: AppSettings) {
        self.settings = settings
        super.init(window: nil)

        buildWindow()
        bindActions()
        refreshLocalization()
        refreshDestinationUI()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func refreshLocalization() {
        window?.title = Localizer.text("Уменьшить размер видеофайла", "Reduce video file size")
        titleLabel.stringValue = Localizer.text("Сжатие видео", "Video compression")
        sourceLabel.stringValue = Localizer.text("Видео файл:", "Video file:")
        targetLabel.stringValue = Localizer.text("Макс. размер:", "Max size:")
        destinationModeLabel.stringValue = Localizer.text("Куда сохранить:", "Save to:")
        chooseSourceButton.title = Localizer.text("Выбрать видео", "Choose video")
        chooseDestinationButton.title = Localizer.text("Выбрать папку", "Choose folder")
        compressButton.title = Localizer.text("Уменьшить", "Compress")

        destinationPopup.removeAllItems()
        destinationPopup.addItems(withTitles: [
            Localizer.text("Папка видео Cliptara", "Cliptara videos folder"),
            Localizer.text("Другая папка", "Custom folder")
        ])

        if destinationPopup.indexOfSelectedItem < 0 {
            destinationPopup.selectItem(at: DestinationMode.videosFolder.rawValue)
        }

        if sourceURL == nil {
            sourcePathField.stringValue = Localizer.text("Не выбрано", "Not selected")
        }

        if statusLabel.stringValue.isEmpty {
            statusLabel.stringValue = Localizer.text("Выберите видео и укажите целевой размер.", "Choose a video and set a target size.")
        }

        refreshDestinationUI()
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 310),
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

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.alignment = .leading
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16)
        ])

        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        root.addArrangedSubview(titleLabel)

        sourcePathField.isBezeled = true
        sourcePathField.isEditable = false
        sourcePathField.isSelectable = true
        sourcePathField.lineBreakMode = .byTruncatingMiddle
        sourcePathField.font = NSFont.systemFont(ofSize: 12)
        sourcePathField.translatesAutoresizingMaskIntoConstraints = false
        sourcePathField.widthAnchor.constraint(equalToConstant: 360).isActive = true
        chooseSourceButton.bezelStyle = .rounded
        chooseSourceButton.translatesAutoresizingMaskIntoConstraints = false
        chooseSourceButton.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let sourceStack = NSStackView(views: [sourcePathField, chooseSourceButton])
        sourceStack.orientation = .horizontal
        sourceStack.spacing = 8
        sourceStack.alignment = .centerY

        targetSizeField.isBezeled = true
        targetSizeField.isEditable = true
        targetSizeField.isSelectable = true
        targetSizeField.alignment = .right
        targetSizeField.delegate = self
        targetSizeField.widthAnchor.constraint(equalToConstant: 140).isActive = true

        targetSuffixLabel.textColor = .secondaryLabelColor
        let targetStack = NSStackView(views: [targetSizeField, targetSuffixLabel])
        targetStack.orientation = .horizontal
        targetStack.spacing = 8
        targetStack.alignment = .centerY

        destinationPopup.translatesAutoresizingMaskIntoConstraints = false
        destinationPopup.widthAnchor.constraint(equalToConstant: 220).isActive = true

        destinationPathField.isBezeled = true
        destinationPathField.isEditable = false
        destinationPathField.isSelectable = true
        destinationPathField.lineBreakMode = .byTruncatingMiddle
        destinationPathField.font = NSFont.systemFont(ofSize: 12)
        destinationPathField.translatesAutoresizingMaskIntoConstraints = false
        destinationPathField.widthAnchor.constraint(equalToConstant: 360).isActive = true

        chooseDestinationButton.bezelStyle = .rounded
        chooseDestinationButton.translatesAutoresizingMaskIntoConstraints = false
        chooseDestinationButton.widthAnchor.constraint(equalToConstant: 130).isActive = true

        let destinationPathStack = NSStackView(views: [destinationPathField, chooseDestinationButton])
        destinationPathStack.orientation = .horizontal
        destinationPathStack.spacing = 8
        destinationPathStack.alignment = .centerY

        let form = NSGridView(views: [
            [sourceLabel, sourceStack],
            [targetLabel, targetStack],
            [destinationModeLabel, destinationPopup],
            [NSTextField(labelWithString: ""), destinationPathStack]
        ])
        form.column(at: 0).width = 130
        form.column(at: 1).width = 500
        form.rowSpacing = 10
        form.columnSpacing = 12
        root.addArrangedSubview(form)

        let separator = NSBox()
        separator.boxType = .separator
        separator.widthAnchor.constraint(equalToConstant: 580).isActive = true
        root.addArrangedSubview(separator)

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.stopAnimation(nil)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.widthAnchor.constraint(equalToConstant: 440).isActive = true

        compressButton.bezelStyle = .rounded
        compressButton.widthAnchor.constraint(equalToConstant: 140).isActive = true

        let actionStack = NSStackView(views: [progressIndicator, statusLabel, compressButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 10
        actionStack.alignment = .centerY
        root.addArrangedSubview(actionStack)
    }

    private func bindActions() {
        chooseSourceButton.target = self
        chooseSourceButton.action = #selector(chooseSourceVideo)

        destinationPopup.target = self
        destinationPopup.action = #selector(destinationModeChanged)

        chooseDestinationButton.target = self
        chooseDestinationButton.action = #selector(chooseDestinationFolder)

        compressButton.target = self
        compressButton.action = #selector(startCompression)
    }

    private func refreshDestinationUI() {
        let mode = DestinationMode(rawValue: max(destinationPopup.indexOfSelectedItem, 0)) ?? .videosFolder
        chooseDestinationButton.isEnabled = mode == .customFolder
        destinationPathField.alphaValue = mode == .customFolder ? 1 : 0.65

        switch mode {
        case .videosFolder:
            destinationPathField.stringValue = settings.videosDirectory.path
        case .customFolder:
            destinationPathField.stringValue = customDestinationDirectory?.path
                ?? Localizer.text("Папка не выбрана", "Folder is not selected")
        }
    }

    private func setBusy(_ busy: Bool) {
        chooseSourceButton.isEnabled = !busy
        destinationPopup.isEnabled = !busy
        chooseDestinationButton.isEnabled = !busy && (DestinationMode(rawValue: destinationPopup.indexOfSelectedItem) == .customFolder)
        compressButton.isEnabled = !busy
        targetSizeField.isEnabled = !busy

        if busy {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
    }

    @objc
    private func chooseSourceVideo() {
        let panel = NSOpenPanel()
        panel.title = Localizer.text("Выберите видеофайл", "Choose a video file")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            sourceURL = url
            sourcePathField.stringValue = url.path
            statusLabel.stringValue = Localizer.text("Готово к сжатию.", "Ready to compress.")
        }
    }

    @objc
    private func destinationModeChanged() {
        refreshDestinationUI()
    }

    @objc
    private func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.title = Localizer.text("Выберите папку назначения", "Choose destination folder")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = customDestinationDirectory ?? settings.videosDirectory

        if panel.runModal() == .OK, let url = panel.url {
            customDestinationDirectory = url
            refreshDestinationUI()
        }
    }

    @objc
    private func startCompression() {
        guard let sourceURL else {
            NSSound.beep()
            statusLabel.stringValue = Localizer.text("Сначала выберите видеофайл.", "Choose a video file first.")
            return
        }

        let targetMB = Int(targetSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        guard targetMB > 0 else {
            NSSound.beep()
            statusLabel.stringValue = Localizer.text("Укажите корректный размер в МБ.", "Enter a valid size in MB.")
            return
        }

        let mode = DestinationMode(rawValue: max(destinationPopup.indexOfSelectedItem, 0)) ?? .videosFolder
        let destinationDirectory: URL
        switch mode {
        case .videosFolder:
            destinationDirectory = settings.videosDirectory
        case .customFolder:
            guard let customDestinationDirectory else {
                NSSound.beep()
                statusLabel.stringValue = Localizer.text("Выберите папку назначения.", "Choose a destination folder.")
                return
            }
            destinationDirectory = customDestinationDirectory
        }

        setBusy(true)
        statusLabel.stringValue = Localizer.text("Сжимаю видео…", "Compressing video…")

        Task { @MainActor in
            defer { setBusy(false) }

            do {
                let result = try await compressor.compress(
                    inputURL: sourceURL,
                    targetSizeMB: targetMB,
                    destinationDirectory: destinationDirectory
                )
                let originalMB = Double(result.originalSizeBytes) / 1_048_576.0
                let outputMB = Double(result.outputSizeBytes) / 1_048_576.0
                let targetText = "\(targetMB) MB"

                if result.metTarget {
                    statusLabel.stringValue = Localizer.text(
                        "Готово: \(String(format: "%.1f", outputMB)) MB (цель \(targetText)).",
                        "Done: \(String(format: "%.1f", outputMB)) MB (target \(targetText))."
                    )
                } else {
                    statusLabel.stringValue = Localizer.text(
                        "Сжал максимально близко: \(String(format: "%.1f", outputMB)) MB (цель \(targetText)).",
                        "Compressed as close as possible: \(String(format: "%.1f", outputMB)) MB (target \(targetText))."
                    )
                }

                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = Localizer.text("Сжатие завершено", "Compression completed")
                alert.informativeText = Localizer.text(
                    "Исходный размер: \(String(format: "%.1f", originalMB)) MB\nНовый размер: \(String(format: "%.1f", outputMB)) MB\nФайл: \(result.outputURL.lastPathComponent)",
                    "Original size: \(String(format: "%.1f", originalMB)) MB\nNew size: \(String(format: "%.1f", outputMB)) MB\nFile: \(result.outputURL.lastPathComponent)"
                )
                alert.addButton(withTitle: Localizer.text("Открыть файл", "Show file"))
                alert.addButton(withTitle: Localizer.text("OK", "OK"))
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([result.outputURL])
                }
            } catch {
                statusLabel.stringValue = error.localizedDescription
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = Localizer.text("Ошибка сжатия", "Compression error")
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: Localizer.text("OK", "OK"))
                alert.runModal()
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField, textField === targetSizeField else {
            return
        }
        let targetMB = Int(targetSizeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 20
        targetSizeField.stringValue = "\(min(max(targetMB, 1), 50_000))"
    }
}
