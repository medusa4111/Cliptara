import Carbon.HIToolbox
import Foundation

final class HotkeyManager {
    private struct HotkeyID {
        static let signature: OSType = 0x6953484B // iSHK
        static let area: UInt32 = 1
        static let full: UInt32 = 2
        static let videoToggle: UInt32 = 3
        static let videoPauseResume: UInt32 = 4
    }

    var onAreaCapture: (() -> Void)?
    var onFullCapture: (() -> Void)?
    var onVideoToggle: (() -> Void)?
    var onVideoPauseResume: (() -> Void)?

    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var currentConfiguration: HotkeyConfiguration?
    private var isEnabled = true

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerHotkeys(configuration: HotkeyConfiguration) {
        currentConfiguration = configuration
        applyCurrentConfiguration()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            return
        }
        isEnabled = enabled
        applyCurrentConfiguration()
    }

    private func installEventHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else {
                    return noErr
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotkeyID = EventHotKeyID()

                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                guard status == noErr else {
                    return status
                }

                manager.handleHotkey(hotkeyID.id)
                return noErr
            },
            1,
            &eventSpec,
            userData,
            &eventHandlerRef
        )
    }

    private func handleHotkey(_ id: UInt32) {
        switch id {
        case HotkeyID.area:
            onAreaCapture?()
        case HotkeyID.full:
            onFullCapture?()
        case HotkeyID.videoToggle:
            onVideoToggle?()
        case HotkeyID.videoPauseResume:
            onVideoPauseResume?()
        default:
            break
        }
    }

    private func register(hotkey: Hotkey, id: UInt32) {
        let eventHotKeyID = EventHotKeyID(signature: HotkeyID.signature, id: id)
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.carbonModifiers,
            eventHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if status == noErr, let hotkeyRef {
            hotkeyRefs.append(hotkeyRef)
        }
    }

    private func unregisterAll() {
        for ref in hotkeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotkeyRefs.removeAll()
    }

    private func applyCurrentConfiguration() {
        unregisterAll()
        guard isEnabled, let configuration = currentConfiguration else {
            return
        }

        register(hotkey: configuration.areaCapture, id: HotkeyID.area)
        register(hotkey: configuration.fullCapture, id: HotkeyID.full)
        register(hotkey: configuration.videoToggle, id: HotkeyID.videoToggle)
        register(hotkey: configuration.videoPauseResume, id: HotkeyID.videoPauseResume)
    }
}
