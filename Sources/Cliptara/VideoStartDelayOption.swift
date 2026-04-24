import Foundation

enum VideoStartDelayOption: Int, CaseIterable {
    case off = 0
    case seconds3 = 3
    case seconds5 = 5

    var title: String {
        switch self {
        case .off:
            return Localizer.text("Без задержки", "No delay")
        case .seconds3:
            return Localizer.text("3 секунды", "3 seconds")
        case .seconds5:
            return Localizer.text("5 секунд", "5 seconds")
        }
    }
}
