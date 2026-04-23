import Foundation

enum AppLanguage: String, CaseIterable {
    case russian
    case english
    case german
    case french
    case spanish
    case chineseSimplified
    case chineseTraditional
    case arabic

    static var defaultFromSystem: AppLanguage {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return .english
        }

        if preferred.hasPrefix("ru") { return .russian }
        if preferred.hasPrefix("de") { return .german }
        if preferred.hasPrefix("fr") { return .french }
        if preferred.hasPrefix("es") { return .spanish }
        if preferred.hasPrefix("ar") { return .arabic }

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
            return "English"
        case .german:
            return "Deutsch"
        case .french:
            return "Français"
        case .spanish:
            return "Español"
        case .chineseSimplified:
            return "简体中文"
        case .chineseTraditional:
            return "繁體中文"
        case .arabic:
            return "العربية"
        }
    }
}
