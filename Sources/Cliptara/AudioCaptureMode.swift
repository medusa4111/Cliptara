import Foundation

enum AudioCaptureMode: String, CaseIterable {
    case system
    case silent
    case systemAndMicrophone
    case microphone

    var capturesSystemAudio: Bool {
        self == .system || self == .systemAndMicrophone
    }

    var capturesMicrophone: Bool {
        self == .microphone || self == .systemAndMicrophone
    }

    var title: String {
        switch self {
        case .system:
            return Localizer.text("Системный звук", "System Audio")
        case .silent:
            return Localizer.text("Без звука", "No Audio")
        case .systemAndMicrophone:
            return Localizer.text("Системный звук + микрофон", "System Audio + Microphone")
        case .microphone:
            return Localizer.text("Только микрофон", "Microphone Only")
        }
    }
}
