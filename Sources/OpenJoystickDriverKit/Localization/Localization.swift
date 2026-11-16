public import Foundation

/// Resolves packaged `Localizable` strings and plurals for the app and CLI.
///
/// Kit owns the resource bundle so the app cannot ship a second catalog.
public struct Localization: Sendable {
  /// The localization of the source catalog.
  public static let sourceLocalization = "en-US"

  /// SwiftPM resource bundle.
  ///
  /// Tests pin this instead of `Bundle.main`.
  public static var moduleBundle: Bundle { .module }

  /// Sentinel that tells a missing key apart from any catalog value.
  private static let missingValue = "\u{0}OJD.missing"

  /// The localizations that the bundle packages.
  private let localizationNames: [String]
  /// The localization selected for the preferred languages; nil when none matches.
  private let localizedLanguage: String?
  /// Preferred locale first, then the `en-US` source catalog.
  private let lookupBundles: [Bundle]
  /// The locale that formats plurals; the current locale when no localization is selected.
  private let formattingLocale: Locale

  /// Creates a resolver for the strings of `bundle`, which defaults to the Kit resource bundle.
  ///
  /// `preferredLanguages` picks the localization; a key it lacks falls back to the source catalog.
  public init(bundle: Bundle? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
    let resolvedBundle = bundle ?? Self.moduleBundle
    let names = Self.availableLocalizations(in: resolvedBundle)
    let language = Self.localizedLanguage(
      among: names,
      preferredLanguages: preferredLanguages
    )
    self.localizationNames = names
    self.localizedLanguage = language
    let preferredBundle = Self.localizedBundle(for: language, in: resolvedBundle)
    let sourceBundle = Self.sourceEnglishBundle(in: resolvedBundle)
    self.lookupBundles = [preferredBundle, sourceBundle].compactMap { $0 }.reduce(into: []) {
      bundles,
      candidate in
      if !bundles.contains(where: { $0.bundleURL == candidate.bundleURL }) {
        bundles.append(candidate)
      }
    }
    if let language {
      self.formattingLocale = Locale(
        identifier: language.replacingOccurrences(of: "-", with: "_")
      )
    } else {
      self.formattingLocale = .current
    }
  }

  /// Best packaged translation for `key`, then the `en-US` source catalog, then the key itself.
  public func string(_ key: String) -> String {
    for bundle in lookupBundles {
      let value = bundle.localizedString(
        forKey: key,
        value: Self.missingValue,
        table: "Localizable"
      )
      if value != Self.missingValue { return value }
    }
    return key
  }

  /// Formats `count` through a `Localizable.stringsdict` plural (`%#@count@`).
  ///
  /// Foundation picks the CLDR category; callers should not branch on `count == 1`.
  public func plural(_ key: String, count: Int) -> String {
    plural(key, arguments: [count])
  }

  /// Formats a `Localizable.stringsdict` plural whose count is one of `arguments`, in the order of
  /// the positions in the entry (`%2$#@count@` reads the second argument ).
  ///
  /// Foundation picks the CLDR category with the locale of the selected localization, so a Russian
  /// entry gets the Russian categories whatever the process locale is. Pass the count as an `Int`.
  public func plural(_ key: String, arguments: [any CVarArg]) -> String {
    unsafe String(format: string(key), locale: formattingLocale, arguments: arguments)
  }

  /// Formats with the user's locale.
  ///
  /// Placeholder types stay those in the source catalog.
  public func string(_ key: String, _ arguments: any CVarArg...) -> String {
    formatted(key, arguments: arguments)
  }

  /// Formats the string for `key` with `arguments` in `locale`.
  public func formatted(
    _ key: String,
    locale: Locale = .current,
    arguments: [any CVarArg]
  ) -> String {
    unsafe String(format: string(key), locale: locale, arguments: arguments)
  }

  /// The localization selected for the injected preference order, if any.
  public var resolvedLanguage: String? { localizedLanguage }

  /// All locale directories that SwiftPM packaged for this resource bundle.
  public var availableLocalizations: [String] { localizationNames }

  /// Returns locale directories present in a bundle, excluding Base resources.
  public static func availableLocalizations(in bundle: Bundle? = nil) -> [String] {
    let resolved = bundle ?? moduleBundle
    if let resourceURL = resolved.resourceURL,
      let entries = try? FileManager.default.contentsOfDirectory(
        at: resourceURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    {
      let directories = entries.compactMap { url -> String? in
        guard url.pathExtension == "lproj" else { return nil }
        return url.deletingPathExtension().lastPathComponent
      }
      if !directories.isEmpty { return directories.sorted() }
    }
    return resolved.localizations.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
      .sorted()
  }

  /// The entry of `localizations` that best matches `preferredLanguages`; nil when none does.
  private static func localizedLanguage(
    among localizations: [String],
    preferredLanguages: [String]
  ) -> String? {
    guard
      let preferred = Bundle.preferredLocalizations(
        from: localizations,
        forPreferences: preferredLanguages
      ).first
    else { return nil }
    return localizations.first { $0.caseInsensitiveCompare(preferred) == .orderedSame }
  }

  /// The `lproj` bundle of `language` inside `bundle`; nil when there is none.
  private static func localizedBundle(for language: String?, in bundle: Bundle) -> Bundle? {
    guard let language, let path = bundle.path(forResource: language, ofType: "lproj") else {
      return nil
    }
    return Bundle(path: path)
  }

  /// The `lproj` bundle of the source catalog inside `bundle`; tries `en-US`, `en`, then `C`.
  private static func sourceEnglishBundle(in bundle: Bundle) -> Bundle? {
    for language in [Self.sourceLocalization, "en", "C"] {
      guard let path = bundle.path(forResource: language, ofType: "lproj"),
        let candidate = Bundle(path: path)
      else { continue }
      return candidate
    }
    return nil
  }
}
