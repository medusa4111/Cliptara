import Foundation

enum ScreenshotFileFormat: String, CaseIterable {
    case png
    case jpg
    case webp

    var fileExtension: String {
        rawValue
    }

    var screencaptureFormat: String {
        rawValue
    }

    var title: String {
        switch self {
        case .png:
            return "PNG"
        case .jpg:
            return "JPG"
        case .webp:
            return "WEBP"
        }
    }
}
