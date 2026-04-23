import AppKit
import Carbon.HIToolbox

final class HotkeyRecorderField: NSTextField {
    var hotkey: Hotkey {
        didSet {
            stringValue = hotkey.displayString
        }
    }

    var onAttemptChange: ((Hotkey) -> Bool)?
    private var keyMonitor: Any?
    private var isCapturing = false

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

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            beginCaptureMode()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        endCaptureMode(restoreDisplay: true)
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if isCapturing {
            capture(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    private func beginCaptureMode() {
        guard !isCapturing else {
            return
        }

        isCapturing = true
        stringValue = Localizer.text("Нажмите сочетание…", "Press shortcut…")

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }
            guard self.isCapturing else {
                return event
            }
            self.capture(event)
            return nil
        }
    }

    private func endCaptureMode(restoreDisplay: Bool) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        isCapturing = false
        if restoreDisplay {
            stringValue = hotkey.displayString
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            endCaptureMode(restoreDisplay: true)
            return
        }

        guard let candidate = Hotkey.from(event: event) else {
            NSSound.beep()
            return
        }

        let isAccepted = onAttemptChange?(candidate) ?? true
        if isAccepted {
            hotkey = candidate
            window?.makeFirstResponder(nil)
        } else {
            NSSound.beep()
            stringValue = hotkey.displayString
        }
    }
}
