import Foundation

/// The 4 languages the LNO Control Center is localized into — mirrors
/// `SUPPORTED_LANGS` in the web dashboard's api/_lib/constants.js exactly (keep
/// both lists in sync if it ever changes). Raw values match the `knownRegions`
/// / .lproj folder names Xcode generates from Localizable.xcstrings, so a
/// `Lang.rawValue` doubles as the language code passed to `Bundle.setLanguage`.
enum Lang: String, CaseIterable, Codable, Identifiable, Equatable {
    case en, fr, de, es

    var id: String { rawValue }
    var displayCode: String { rawValue.uppercased() }
    /// Passed to `.environment(\.locale, …)` to force SwiftUI's `Text`/
    /// `LocalizedStringKey` resolution (and number/date formatting) to this
    /// language, independent of the device's system Settings ▸ Language.
    var locale: Locale { Locale(identifier: rawValue) }
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }

    /// Best-effort match against the device's preferred language, falling back to
    /// `.en` — used the very first time the app launches with no stored choice
    /// and no signed-in account (mirrors the web's `detectBrowserLang()`).
    static func detectDeviceLanguage() -> Lang {
        for code in Locale.preferredLanguages {
            let base = String(code.prefix(2)).lowercased()
            if let match = Lang(rawValue: base) { return match }
        }
        return .en
    }
}

/// Reads/writes the user's chosen language to the same App Group container the
/// widget snapshot uses, so both the main app process and the widget extension
/// process (which never runs `LanguageStore`) see the same choice. The plain
/// `UserDefaults.standard` copy makes the choice survive a signed-out relaunch too.
enum LanguagePersistence {
    private static let key = "lno_selected_language"

    static func load() -> Lang? {
        if let raw = UserDefaults.standard.string(forKey: key), let l = Lang(rawValue: raw) { return l }
        // First launch on this device may already have an App Group value (e.g.
        // restored from an old install) even if standard defaults were cleared.
        if let raw = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.string(forKey: key), let l = Lang(rawValue: raw) { return l }
        return nil
    }

    static func save(_ lang: Lang) {
        UserDefaults.standard.set(lang.rawValue, forKey: key)
        UserDefaults(suiteName: WidgetSnapshot.appGroup)?.set(lang.rawValue, forKey: key)
    }

    /// The .lproj bundle for the chosen language, for string lookups that must NOT rely on
    /// `.environment(\.locale, …)`.
    ///
    /// That environment override does drive Text/LocalizedStringKey in ordinary widgets, but
    /// it does NOT reach a Live Activity's presentation — verified on the Simulator with the
    /// App Group language set to `fr` and the fr.lproj present in the .appex: the card still
    /// rendered the English source strings. Looking the string up explicitly is the only way
    /// to make a Live Activity honour the in-app language choice.
    static func bundleForWidget() -> Bundle {
        let lang = loadForWidget().rawValue
        guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    /// Localized lookup through `bundleForWidget()`. `key` is the English source string, the
    /// same key Localizable.xcstrings is keyed by, so nothing has to be kept in sync by hand.
    static func widgetString(_ key: String) -> String {
        bundleForWidget().localizedString(forKey: key, value: key, table: nil)
    }

    /// Widget-extension-side read (no `UserDefaults.standard` access needed there).
    static func loadForWidget() -> Lang {
        guard let raw = UserDefaults(suiteName: WidgetSnapshot.appGroup)?.string(forKey: key), let l = Lang(rawValue: raw) else {
            return .detectDeviceLanguage()
        }
        return l
    }
}
