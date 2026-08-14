import Foundation

/// Resolves user-facing strings from the Kit-owned localization resources.
///
/// The application target uses this bridge for AppKit-owned text, SwiftUI text
/// that needs an eagerly resolved `String`, and accessibility/help copy. The
/// bundle is deliberately owned by the Kit target so the app and its nested
/// resource bundle cannot drift apart.
public struct Localization: @unchecked Sendable {
  public static let sourceLocalization = "en-US"

  /// The package resource bundle, exposed for deterministic product/resource tests.
  public static var moduleBundle: Bundle { .module }

  private let bundle: Bundle
  private let preferredLanguages: [String]

  public init(bundle: Bundle? = nil, preferredLanguages: [String] = Locale.preferredLanguages) {
    self.bundle = bundle ?? Self.moduleBundle
    self.preferredLanguages = preferredLanguages
  }

  /// Returns the best available translation, falling back to `defaultValue`
  /// (or the key itself) when a table does not contain the requested entry.
  public func string(_ key: String, defaultValue: String? = nil, comment: String = "") -> String {
    let fallback = defaultValue ?? key
    guard let preferredBundle = localizedBundle() else { return fallback }

    let value = NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: preferredBundle,
      value: fallback,
      comment: comment
    )
    guard value == fallback, !isSourceLanguage else { return value }

    // A partially translated locale should fall back to the source English
    // resource rather than exposing a key or an empty label.
    guard let sourceBundle = sourceEnglishBundle(), sourceBundle !== preferredBundle else {
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

  /// Resolves a native Foundation plural resource and formats it with `count`.
  ///
  /// The resource must be a `Localizable.stringsdict` entry whose format key
  /// references a plural variable (for example `%#@count@`). Foundation then
  /// selects the locale's CLDR category (`one`, `few`, `many`, `zero`, and so
  /// on) instead of making the caller guess from `count == 1`.
  public func plural(_ key: String, count: Int, defaultValue: String? = nil, comment: String = "")
    -> String
  {
    let fallback = defaultValue ?? key
    guard let preferredBundle = localizedBundle() else {
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

    // A partially translated locale may omit the plural entry. Resolve the
    // source-English resource before formatting so the caller never receives
    // a key or a raw `%#@count@` format string.
    guard let sourceBundle = sourceEnglishBundle() else {
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

  /// Formats a localized string with the user's locale while preserving the
  /// placeholder types authored in the source catalog.
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
  public var availableLocalizations: [String] { Self.availableLocalizations(in: bundle) }

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

  /// Returns the keys in a packaged `.strings` table. This is intentionally a
  /// resource-level API for tests and release diagnostics, not a source-text
  /// inspection path.
  public static func catalogKeys(
    for localization: String = sourceLocalization,
    bundle: Bundle? = nil
  ) -> Set<String> {
    let bundle = bundle ?? moduleBundle
    var keys = stringsData(for: localization, in: bundle).map { Set(parseStrings($0).keys) } ?? []
    keys.formUnion(parseStringsDictData(for: localization, in: bundle).keys)
    return keys
  }

  /// Returns placeholder signatures (`%@`, `%d`, and so on) for a packaged
  /// table. Comparing signatures catches a translation that drops or changes
  /// a value placeholder while allowing natural word order per locale.
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

  /// Returns the category keys in each packaged plural resource. This keeps
  /// structural validation independent from the prose of a translation.
  public static func catalogPluralCategories(
    for localization: String = sourceLocalization,
    bundle: Bundle? = nil
  ) -> [String: Set<String>] {
    parseStringsDictCategories(for: localization, in: bundle ?? moduleBundle)
  }

  private var localizedLanguage: String? {
    let localizations = Self.availableLocalizations(in: bundle)
    guard
      let preferred = Bundle.preferredLocalizations(
        from: localizations,
        forPreferences: preferredLanguages
      ).first
    else { return nil }
    return localizations.first { $0.caseInsensitiveCompare(preferred) == .orderedSame }
  }

  private var isSourceLanguage: Bool {
    localizedLanguage?.caseInsensitiveCompare(Self.sourceLocalization) == .orderedSame
  }

  private var formattingLocale: Locale {
    guard let localizedLanguage else { return .current }
    return Locale(identifier: localizedLanguage.replacingOccurrences(of: "-", with: "_"))
  }

  private func localizedBundle() -> Bundle? {
    guard let language = localizedLanguage,
      let path = bundle.path(forResource: language, ofType: "lproj")
    else { return nil }
    return Bundle(path: path)
  }

  private func sourceEnglishBundle() -> Bundle? {
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
