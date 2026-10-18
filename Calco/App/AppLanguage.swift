import Foundation

/// The app's language: English by default whatever the iPad's language, Spanish from Preferences.
/// Text in views follows the root view's `locale`; strings built in code are looked up in
/// `AppLanguage.bundle` (`String(localized: …, bundle: AppLanguage.bundle)`). The choice is also the
/// app's preferred language for the system, so the next launch starts in it.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"

    var id: String { rawValue }
    /// Each language in its own words, so it's findable whichever one is on.
    var name: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }

    private static let key = "app.language"

    static var saved: AppLanguage {
        UserDefaults.standard.string(forKey: key).flatMap(AppLanguage.init) ?? .english
    }

    /// Where strings built in code come from. English's table is empty, so the key (the English
    /// text) comes back, even on an iPad set to Spanish.
    nonisolated(unsafe) private(set) static var bundle = Bundle.main

    static func apply(_ language: AppLanguage, save: Bool = true) {
        if save { UserDefaults.standard.set(language.rawValue, forKey: key) }
        // The system's own texts and the next launch follow the app's language, not the iPad's.
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}
