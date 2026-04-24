import AppKit
import Carbon.HIToolbox
import Foundation

struct Hotkey: Codable, Equatable {
    let keyCode: UInt32
    let carbonModifiers: UInt32

    var displayString: String {
        var result = ""

        if carbonModifiers & UInt32(controlKey) != 0 {
            result += "^"
        }
        if carbonModifiers & UInt32(optionKey) != 0 {
            result += "⌥"
        }
        if carbonModifiers & UInt32(shiftKey) != 0 {
            result += "⇧"
        }
        if carbonModifiers & UInt32(cmdKey) != 0 {
            result += "⌘"
        }

        result += Self.keySymbol(for: keyCode)
        return result
    }

    func matches(_ other: Hotkey) -> Bool {
        keyCode == other.keyCode && carbonModifiers == other.carbonModifiers
    }

    static func from(event: NSEvent) -> Hotkey? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }

        guard carbon != 0 else {
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        if Self.isModifierKey(keyCode) {
            return nil
        }

        return Hotkey(keyCode: keyCode, carbonModifiers: carbon)
    }

    static func keySymbol(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_ANSI_A): return "A"
        case UInt32(kVK_ANSI_B): return "B"
        case UInt32(kVK_ANSI_C): return "C"
        case UInt32(kVK_ANSI_D): return "D"
        case UInt32(kVK_ANSI_E): return "E"
        case UInt32(kVK_ANSI_F): return "F"
        case UInt32(kVK_ANSI_G): return "G"
        case UInt32(kVK_ANSI_H): return "H"
        case UInt32(kVK_ANSI_I): return "I"
        case UInt32(kVK_ANSI_J): return "J"
        case UInt32(kVK_ANSI_K): return "K"
        case UInt32(kVK_ANSI_L): return "L"
        case UInt32(kVK_ANSI_M): return "M"
        case UInt32(kVK_ANSI_N): return "N"
        case UInt32(kVK_ANSI_O): return "O"
        case UInt32(kVK_ANSI_P): return "P"
        case UInt32(kVK_ANSI_Q): return "Q"
        case UInt32(kVK_ANSI_R): return "R"
        case UInt32(kVK_ANSI_S): return "S"
        case UInt32(kVK_ANSI_T): return "T"
        case UInt32(kVK_ANSI_U): return "U"
        case UInt32(kVK_ANSI_V): return "V"
        case UInt32(kVK_ANSI_W): return "W"
        case UInt32(kVK_ANSI_X): return "X"
        case UInt32(kVK_ANSI_Y): return "Y"
        case UInt32(kVK_ANSI_Z): return "Z"
        case UInt32(kVK_ANSI_0): return "0"
        case UInt32(kVK_ANSI_1): return "1"
        case UInt32(kVK_ANSI_2): return "2"
        case UInt32(kVK_ANSI_3): return "3"
        case UInt32(kVK_ANSI_4): return "4"
        case UInt32(kVK_ANSI_5): return "5"
        case UInt32(kVK_ANSI_6): return "6"
        case UInt32(kVK_ANSI_7): return "7"
        case UInt32(kVK_ANSI_8): return "8"
        case UInt32(kVK_ANSI_9): return "9"
        case UInt32(kVK_ANSI_Grave): return "`"
        case UInt32(kVK_Space): return Localizer.text("Пробел", "Space")
        case UInt32(kVK_Return): return "↩"
        case UInt32(kVK_Escape): return "⎋"
        case UInt32(kVK_Delete): return "⌫"
        case UInt32(kVK_ForwardDelete): return "⌦"
        case UInt32(kVK_Tab): return "⇥"
        case UInt32(kVK_LeftArrow): return "←"
        case UInt32(kVK_RightArrow): return "→"
        case UInt32(kVK_UpArrow): return "↑"
        case UInt32(kVK_DownArrow): return "↓"
        default:
            return "?"
        }
    }

    private static func isModifierKey(_ keyCode: UInt32) -> Bool {
        let modifiers: Set<UInt32> = [
            UInt32(kVK_Command), UInt32(kVK_RightCommand),
            UInt32(kVK_Shift), UInt32(kVK_RightShift),
            UInt32(kVK_Option), UInt32(kVK_RightOption),
            UInt32(kVK_Control), UInt32(kVK_RightControl),
            UInt32(kVK_CapsLock), UInt32(kVK_Function)
        ]
        return modifiers.contains(keyCode)
    }
}

struct HotkeyConfiguration: Codable, Equatable {
    var areaCapture: Hotkey
    var fullCapture: Hotkey
    var videoToggle: Hotkey
    var videoPauseResume: Hotkey

    private enum CodingKeys: String, CodingKey {
        case areaCapture
        case fullCapture
        case videoToggle
        case videoPauseResume
    }

    init(areaCapture: Hotkey, fullCapture: Hotkey, videoToggle: Hotkey, videoPauseResume: Hotkey) {
        self.areaCapture = areaCapture
        self.fullCapture = fullCapture
        self.videoToggle = videoToggle
        self.videoPauseResume = videoPauseResume
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        areaCapture = try container.decode(Hotkey.self, forKey: .areaCapture)
        fullCapture = try container.decode(Hotkey.self, forKey: .fullCapture)
        videoToggle = try container.decodeIfPresent(Hotkey.self, forKey: .videoToggle)
            ?? Hotkey(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(controlKey))
        videoPauseResume = try container.decodeIfPresent(Hotkey.self, forKey: .videoPauseResume)
            ?? Hotkey(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(controlKey))
    }

    static let `default` = HotkeyConfiguration(
        areaCapture: Hotkey(keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: UInt32(controlKey)),
        fullCapture: Hotkey(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(controlKey)),
        videoToggle: Hotkey(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(controlKey)),
        videoPauseResume: Hotkey(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(controlKey))
    )
}
