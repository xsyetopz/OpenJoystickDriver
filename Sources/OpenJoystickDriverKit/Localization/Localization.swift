import Foundation

/// Resolves packaged `Localizable` strings and plurals for the app and CLI.
///
/// Kit owns the resource bundle so the app cannot ship a second catalog.
public struct Localization: @unchecked Sendable {
  public static let sourceLocalization = "en-US"

  /// SwiftPM resource bundle. Tests pin this instead of `Bundle.main`.
  public static var moduleBundle: Bundle { .module }

  private let localizationNames: [String]
  private let localizedLanguage: String?
  private let preferredBundle: Bundle?
  private let sourceEnglishBundle: Bundle?
  private let isSourceLanguage: Bool
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
    self.preferredBundle = Self.localizedBundle(for: localizedLanguage, in: bundle)
    self.sourceEnglishBundle = Self.sourceEnglishBundle(in: bundle)
    self.isSourceLanguage =
      localizedLanguage?.caseInsensitiveCompare(Self.sourceLocalization) == .orderedSame
    if let localizedLanguage {
      self.formattingLocale = Locale(
        identifier: localizedLanguage.replacingOccurrences(of: "-", with: "_")
      )
    } else {
      self.formattingLocale = .current
    }
  }

  /// Best packaged translation for `key`, then `defaultValue`, then the key.
  public func string(_ key: String, defaultValue: String? = nil, comment: String = "") -> String {
    let fallback = defaultValue ?? key
    guard let preferredBundle else { return fallback }

    let value = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: preferredBundle,
      value: fallback,
      comment: comment
    )
    guard value == fallback, !isSourceLanguage else { return value }

    // Incomplete locale: prefer source English over a raw key.
    guard let sourceBundle = sourceEnglishBundle, sourceBundle !== preferredBundle else {
      return value
    }
    return NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: sourceBundle,
      value: fallback,
      comment: comment
    )
  }

  /// Formats `count` through a `Localizable.stringsdict` plural (`%#@count@`).
  /// Foundation picks the CLDR category; callers should not branch on `count == 1`.
  public func plural(_ key: String, count: Int, defaultValue: String? = nil, comment: String = "")
    -> String
  {
    let fallback = defaultValue ?? key
    guard let preferredBundle else {
      return Self.format(fallback, count: count, locale: formattingLocale)
    }

    let value = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: preferredBundle,
      value: fallback,
      comment: comment
    )
    guard value == fallback, !isSourceLanguage else {
      return Self.format(value, count: count, locale: formattingLocale)
    }

    // Incomplete locale: format source English, not a raw `%#@count@` string.
    guard let sourceBundle = sourceEnglishBundle else {
      return Self.format(value, count: count, locale: formattingLocale)
    }
    let sourceValue = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: sourceBundle,
      value: fallback,
      comment: comment
    )
    return Self.format(sourceValue, count: count, locale: formattingLocale)
  }

  /// Formats with the user's locale. Placeholder types stay those in the source catalog.
  public func string(_ key: String, _ arguments: CVarArg...) -> String {
    formatted(key, arguments: arguments)
  }

  public func formatted(
    _ key: String,
    defaultValue: String? = nil,
    locale: Locale = .current,
    arguments: [CVarArg]
  ) -> String {
    String(format: string(key, defaultValue: defaultValue), locale: locale, arguments: arguments)
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

  /// Keys in a packaged `.strings` table. For tests and diagnostics, not source inspection.
  public static func catalogKeys(
    for localization: String = sourceLocalization,
    bundle: Bundle? = nil
  ) -> Set<String> {
    let bundle = bundle ?? moduleBundle
    var keys = stringsData(for: localization, in: bundle).map { Set(parseStrings($0).keys) } ?? []
    keys.formUnion(parseStringsDictData(for: localization, in: bundle).keys)
    return keys
  }

  /// Placeholder tokens (`%@`, `%d`, ...) per key. Word order may differ; signatures must not.
  public static func catalogPlaceholderSignatures(
    for localization: String = sourceLocalization,
    bundle: Bundle? = nil
  ) -> [String: [String]] {
    let bundle = bundle ?? moduleBundle
    var result =
      stringsData(for: localization, in: bundle).map {
        parseStrings($0).mapValues { placeholderSignature(in: $0) }
      } ?? [:]
    for (key, values) in parseStringsDictData(for: localization, in: bundle) {
      result[key] = values.flatMap { placeholderSignature(in: $0) }.sorted()
    }
    return result
  }

  /// Plural category keys per resource. Structural check; ignores translation prose.
  public static func catalogPluralCategories(
    for localization: String = sourceLocalization,
    bundle: Bundle? = nil
  ) -> [String: Set<String>] {
    parseStringsDictCategories(for: localization, in: bundle ?? moduleBundle)
  }

  private static func localizedLanguage(among localizations: [String], preferredLanguages: [String])
    -> String?
  {
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

  private static func stringsData(for localization: String, in bundle: Bundle) -> Data? {
    guard
      let path = bundle.path(
        forResource: "Localizable",
        ofType: "strings",
        inDirectory: "\(localization).lproj"
      )
    else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func stringsDictData(for localization: String, in bundle: Bundle) -> Data? {
    guard
      let path = bundle.path(
        forResource: "Localizable",
        ofType: "stringsdict",
        inDirectory: "\(localization).lproj"
      )
    else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func parseStringsDictData(for localization: String, in bundle: Bundle) -> [String:
    [String]]
  {
    guard let data = stringsDictData(for: localization, in: bundle),
      let propertyList = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ), let dictionary = propertyList as? [String: Any]
    else { return [:] }

    return dictionary.reduce(into: [:]) { result, entry in
      var strings: [String] = []
      collectPluralStrings(entry.value, into: &strings)
      result[entry.key] = strings
    }
  }

  private static func parseStringsDictCategories(for localization: String, in bundle: Bundle)
    -> [String: Set<String>]
  {
    guard let data = stringsDictData(for: localization, in: bundle),
      let propertyList = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ), let dictionary = propertyList as? [String: Any]
    else { return [:] }

    return dictionary.reduce(into: [:]) { result, entry in
      result[entry.key] = collectPluralCategories(entry.value)
    }
  }

  private static func collectPluralStrings(_ value: Any, into strings: inout [String]) {
    if let string = value as? String {
      strings.append(string)
      return
    }
    guard let dictionary = value as? [String: Any] else { return }
    for (key, child) in dictionary where !key.hasPrefix("NSString") {
      collectPluralStrings(child, into: &strings)
    }
  }

  private static func collectPluralCategories(_ value: Any) -> Set<String> {
    guard let dictionary = value as? [String: Any] else { return [] }
    if dictionary["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
      return Set(dictionary.keys.filter { !$0.hasPrefix("NSString") })
    }
    return dictionary.values.reduce(into: Set<String>()) { result, child in
      result.formUnion(collectPluralCategories(child))
    }
  }

  private static func parseStrings(_ data: Data) -> [String: String] {
    guard let text = String(data: data, encoding: .utf8) else { return [:] }
    let pattern = #""((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    var result: [String: String] = [:]
    expression.enumerateMatches(in: text, range: range) { match, _, _ in
      guard let match, let keyRange = Range(match.range(at: 1), in: text),
        let valueRange = Range(match.range(at: 2), in: text)
      else { return }
      result[unescape(String(text[keyRange]))] = unescape(String(text[valueRange]))
    }
    return result
  }

  private static func unescape(_ value: String) -> String {
    value.replacingOccurrences(of: #"\\"#, with: #"\"#).replacingOccurrences(of: #"\n"#, with: "\n")
      .replacingOccurrences(of: #"\\"#, with: "\\")
  }

  private static func placeholderSignature(in value: String) -> [String] {
    let pattern = #"%(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z]"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
  }

  private static func format(_ value: String, count: Int, locale: Locale) -> String {
    String(format: value, locale: locale, arguments: [count])
  }
}
