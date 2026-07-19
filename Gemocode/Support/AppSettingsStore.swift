import SwiftUI

// MARK: - Appearance & language preferences
//
// A tiny settings store, exposed as a singleton `ObservableObject` so both
// the app root (`GemocodeApp`, which needs to react to changes to drive
// `.preferredColorScheme`/`.environment(\.locale)`) and Profile & Settings
// (which just needs bindings for the pickers) share the same live values —
// the same `.shared` pattern `PremiumStore` uses. Gemocode's glass design
// system (`Support/Theme.swift`) was built dark-only, so `.dark` stays the
// default even though System/Light are now offered.

/// User's theme preference. `.dark` is the historical default.
enum ThemeChoice: String, CaseIterable {
    case system, dark, light

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .dark: String(localized: "Dark")
        case .light: String(localized: "Light")
        }
    }

    /// `nil` tells `.preferredColorScheme` to defer to the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .dark: .dark
        case .light: .light
        }
    }
}

/// User's language preference. `.system` (the default) leaves the app on
/// whatever the device/system language resolves to.
enum LanguageChoice: String, CaseIterable {
    case system
    case english = "en"
    case russian = "ru"

    var displayName: String {
        switch self {
        case .system: String(localized: "System")
        case .english: String(localized: "English")
        case .russian: String(localized: "Русский")
        }
    }

    /// `nil` leaves the SwiftUI `\.locale` environment value untouched.
    var localeOverride: Locale? {
        switch self {
        case .system: nil
        case .english, .russian: Locale(identifier: rawValue)
        }
    }
}

/// Live appearance/language settings, persisted to `UserDefaults`.
///
/// Reads/writes `UserDefaults` directly (rather than the `@AppStorage`
/// property wrapper, which targets `View`/`DynamicProperty` contexts) so
/// this can be a plain `ObservableObject` singleton: every mutation goes
/// through `didSet`, which persists it and — via `@Published` — notifies
/// observers (the app root's `.preferredColorScheme`/`.environment(\.locale)`
/// and the Profile pickers) immediately.
@MainActor
final class AppSettingsStore: ObservableObject {
    /// Shared instance — mirrors `PremiumStore.shared` so views can bind to
    /// it directly via `@ObservedObject` without requiring an
    /// `environmentObject` injection at every call site.
    static let shared = AppSettingsStore()

    static let themeKey = "app.theme"
    static let languageKey = "app.language"

    /// The `UserDefaults` key Foundation/UIKit consult for bundle-level
    /// string lookups (`String(localized:)`, `Bundle.main.localizedString`,
    /// etc.) starting on the *next* launch. SwiftUI's `\.locale` environment
    /// (set from `languageChoice` at the app root) covers live `Text`
    /// immediately; this covers everything else after a relaunch.
    private static let appleLanguagesKey = "AppleLanguages"

    @Published var themeChoice: ThemeChoice {
        didSet {
            guard themeChoice != oldValue else { return }
            UserDefaults.standard.set(themeChoice.rawValue, forKey: Self.themeKey)
        }
    }

    @Published var languageChoice: LanguageChoice {
        didSet {
            guard languageChoice != oldValue else { return }
            UserDefaults.standard.set(languageChoice.rawValue, forKey: Self.languageKey)
            Self.applyAppleLanguages(languageChoice)
        }
    }

    private init() {
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        themeChoice = storedTheme.flatMap(ThemeChoice.init(rawValue:)) ?? .dark
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
        languageChoice = storedLanguage.flatMap(LanguageChoice.init(rawValue:)) ?? .system
    }

    private static func applyAppleLanguages(_ choice: LanguageChoice) {
        switch choice {
        case .system:
            UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
        case .english, .russian:
            UserDefaults.standard.set([choice.rawValue], forKey: appleLanguagesKey)
        }
    }
}
