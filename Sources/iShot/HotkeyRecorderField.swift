import AppKit

final class HotkeyRecorderField: NSTextField {
    var hotkey: Hotkey {
        didSet {
            stringValue = hotkey.displayString
        }
    }

    var onAttemptChange: ((Hotkey) -> Bool)?

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
        super.init(frame: .zero)
        configure()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    private func configure() {
        isEditable = false
        isSelectable = false
        isBezeled = true
        bezelStyle = .roundedBezel
        alignment = .center
        font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        focusRingType = .default
        stringValue = hotkey.displayString
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let candidate = Hotkey.from(event: event) else {
            NSSound.beep()
            return
        }

        let isAccepted = onAttemptChange?(candidate) ?? true
        if isAccepted {
            hotkey = candidate
        } else {
            NSSound.beep()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }
}
