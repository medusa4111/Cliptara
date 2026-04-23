import Foundation

enum AudioCaptureMode: String, CaseIterable {
    case system
    case silent

    var capturesSystemAudio: Bool {
        switch self {
        case .system:
            return true
        case .silent:
            return false
        }
    }

    var title: String {
        switch self {
        case .system:
            return Localizer.text("Системный звук", "System Audio")
        case .silent:
            return Localizer.text("Без звука", "No Audio")
        }
    }
}
