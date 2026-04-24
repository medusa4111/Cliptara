import Foundation

enum VideoQualityPreset: String, CaseIterable {
    case high
    case balanced
    case small

    var targetBitrateKbps: Int {
        switch self {
        case .high:
            return 12_000
        case .balanced:
            return 7_000
        case .small:
            return 4_000
        }
    }

    var title: String {
        switch self {
        case .high:
            return Localizer.text("Высокое", "High")
        case .balanced:
            return Localizer.text("Сбалансированное", "Balanced")
        case .small:
            return Localizer.text("Компактное", "Small")
        }
    }
}
