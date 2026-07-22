import Foundation

enum AppLanguage: String, CaseIterable {
    case russian
    case english
    case polish
    case chineseSimplified
    case chineseTraditional

    static var defaultFromSystem: AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .english
        }

        if preferred.hasPrefix("ru") { return .russian }
        if preferred.hasPrefix("pl") { return .polish }

        if preferred.hasPrefix("zh-hant")
            || preferred.hasPrefix("zh-tw")
            || preferred.hasPrefix("zh-hk")
            || preferred.contains("hant") {
            return .chineseTraditional
        }
        if preferred.hasPrefix("zh") {
            return .chineseSimplified
        }

        return .english
    }

    var nativeName: String {
        switch self {
        case .russian:
            return "Русский"
        case .english:
            return "English (US)"
        case .polish:
            return "Polski"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        }
    }
}
