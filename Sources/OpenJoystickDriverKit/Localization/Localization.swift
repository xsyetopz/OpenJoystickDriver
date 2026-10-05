import Foundation

/// Resolves packaged `Localizable` strings and plurals for the app and CLI.
///
/// Kit owns the resource bundle so the app cannot ship a second catalog.
public struct Localization: Sendable {
  public static let sourceLocalization = "en-US"

  /// SwiftPM resource bundle. Tests pin this instead of `Bundle.main`.
  public static var moduleBundle: Bundle { .module }

  /// Sentinel that tells a missing key apart from any catalog value.
  private static let missingValue = "\u{0}OJD.missing"

  private let localizationNames: [String]
  private let localizedLanguage: String?
  /// Preferred locale first, then the `en-US` source catalog.
  private let lookupBundles: [Bundle]
  private let formattingLocale: Locale

  public init(bundle: Bundle? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
    let bundle = bundle ?? Self.moduleBundle
    let localizationNames = Self.availableLocalizations(in: bundle)
    let localizedLanguage = Self.localizedLanguage(
      among: localizationNames,
      preferredLanguages: preferredLanguages
    )
    self.localizationNames = localizationNames
    self.localizedLanguage = localizedLanguage
    let preferredBundle = Self.localizedBundle(for: localizedLanguage, in: bundle)
    let sourceBundle = Self.sourceEnglishBundle(in: bundle)
    self.lookupBundles = [preferredBundle, sourceBundle].compactMap { $0 }.reduce(into: []) {
      bundles,
      candidate in
      if !bundles.contains(where: { $0.bundleURL == candidate.bundleURL }) {
        bundles.append(candidate)
      }
    }
    if let localizedLanguage {
      self.formattingLocale = Locale(
        identifier: localizedLanguage.replacingOccurrences(of: "-", with: "_")
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
  /// Foundation picks the CLDR category; callers should not branch on `count == 1`.
  public func plural(_ key: String, count: Int) -> String {
    Self.format(string(key), count: count, locale: formattingLocale)
  }

  /// Formats with the user's locale. Placeholder types stay those in the source catalog.
  public func string(_ key: String, _ arguments: CVarArg...) -> String {
    formatted(key, arguments: arguments)
  }

  public func formatted(_ key: String, locale: Locale = .current, arguments: [CVarArg]) -> String {
    String(format: string(key), locale: locale, arguments: arguments)
  }

  /// The localization selected for the injected preference order, if any.
  public var resolvedLanguage: String? { localizedLanguage }

  /// All locale directories that SwiftPM packaged for this resource bundle.
  public var availableLocalizations: [String] { localizationNames }

  /// Returns locale directories present in a bundle, excluding Base resources.
  public static func availableLocalizations(in bundle: Bundle? = nil) -> [String] {
    let bundle = bundle ?? moduleBundle
    if let resourceURL = bundle.resourceURL,
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
    return bundle.localizations.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }
      .sorted()
  }

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

  private static func localizedBundle(for language: String?, in bundle: Bundle) -> Bundle? {
    guard let language, let path = bundle.path(forResource: language, ofType: "lproj") else {
      return nil
    }
    return Bundle(path: path)
  }

  private static func sourceEnglishBundle(in bundle: Bundle) -> Bundle? {
    for language in [Self.sourceLocalization, "en", "C"] {
      guard let path = bundle.path(forResource: language, ofType: "lproj"),
        let candidate = Bundle(path: path)
      else { continue }
      return candidate
    }
    return nil
  }

  private static func format(_ value: String, count: Int, locale: Locale) -> String {
    String(format: value, locale: locale, arguments: [count])
  }
}
