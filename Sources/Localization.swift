import Foundation

// UI text is localized with the English text as the key. Translations live in
// Resources/<language>.lproj/Localizable.strings; any language without a translation falls back to English.
// scripts/check-localizations.swift (run by build.sh) checks that every language has every key.

/// Localized text.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized printf-style format (%@, %ld, %% for a literal percent sign).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments: args)
}
