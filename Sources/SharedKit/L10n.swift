// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Localized-string lookup with an in-app language override. The chosen
// language lives in ApplicationConfig (InterfaceLanguage), not in
// UserDefaults/AppleLanguages, so Foundation's automatic locale resolution
// never sees it - apply(languageCode:) must run once at startup before any
// UI is built. Language changes take effect on relaunch; L10n is an
// ObservableObject so live switching can be added later without touching
// call sites.
//
// Lookup order: selected-language bundle -> en bundle -> the key itself.
// Translations are one file per language:
// Sources/SharedKit/Resources/<code>.lproj/Localizable.strings
// (see /docs/LOCALIZATION.md for the contributor guide).

import Foundation

public final class L10n: ObservableObject {
    public static let shared = L10n()

    /// BCP-47 code of the active override; nil = follow the system language.
    @Published public private(set) var overrideCode: String?

    private var activeBundle: Bundle
    private let englishBundle: Bundle

    /// Sentinel default that no .strings file will ever contain, so a miss is
    /// distinguishable from a key whose translation equals the key.
    private static let missing = "\u{7}\u{7}"

    private init() {
        let english = L10n.bundle(for: "en") ?? Bundle.module
        englishBundle = english
        activeBundle = L10n.systemPreferredBundle() ?? english
    }

    /// Languages shipped in the resource bundle, e.g. ["en", "fr"].
    public static var availableLanguages: [String] {
        Bundle.module.localizations.filter { $0 != "Base" }.sorted()
    }

    /// Point lookups at `code`; nil or an unshipped code falls back to the
    /// system-preferred shipped language, then English.
    public func apply(languageCode code: String?) {
        overrideCode = code
        if let code, let bundle = L10n.bundle(for: code) {
            activeBundle = bundle
        } else {
            activeBundle = L10n.systemPreferredBundle() ?? englishBundle
        }
    }

    public func string(_ key: String) -> String {
        let value = activeBundle.localizedString(forKey: key, value: L10n.missing, table: nil)
        if value != L10n.missing { return value }
        let english = englishBundle.localizedString(forKey: key, value: L10n.missing, table: nil)
        return english == L10n.missing ? key : english
    }

    public func string(_ key: String, _ args: [CVarArg]) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }

    /// Shorthand used at call sites: `L10n.t("menu.capture_region")`.
    public static func t(_ key: String) -> String { shared.string(key) }

    /// Format variant: `L10n.t("upload.count", files.count)`.
    public static func t(_ key: String, _ args: CVarArg...) -> String { shared.string(key, args) }

    /// True when `key` has a translation in the active or English table.
    /// Lets call sites keep a computed default for keys not yet translated.
    public static func has(_ key: String) -> Bool { t(key) != key }

    /// Picker label: the language's own name for itself, plus the English
    /// name when they differ - e.g. "Deutsch (German)".
    public static func displayName(for code: String) -> String {
        let native = Locale(identifier: code).localizedString(forIdentifier: code)
        let english = Locale(identifier: "en").localizedString(forIdentifier: code)
        guard let native else { return english ?? code }
        guard let english, english.caseInsensitiveCompare(native) != .orderedSame else {
            return native.capitalized(with: Locale(identifier: code))
        }
        return "\(native.capitalized(with: Locale(identifier: code))) (\(english))"
    }

    private static func bundle(for code: String) -> Bundle? {
        Bundle.module.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    private static func systemPreferredBundle() -> Bundle? {
        let preferred = Bundle.preferredLocalizations(from: availableLanguages,
                                                      forPreferences: Locale.preferredLanguages)
        return preferred.first.flatMap(bundle(for:))
    }
}
