import Foundation

enum ScreenshotAction: String, CaseIterable {
    case copyToClipboard
    case saveToFiles
    case copyAndSave

    var title: String {
        switch self {
        case .copyToClipboard:
            return Localizer.text("Копировать в буфер", "Copy to clipboard")
        case .saveToFiles:
            return Localizer.text("Сохранить", "Save")
        case .copyAndSave:
            return Localizer.text("Копировать и сохранить", "Copy and save")
        }
    }
}
