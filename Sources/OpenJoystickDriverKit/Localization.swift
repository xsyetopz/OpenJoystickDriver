import Foundation

public struct Localization: Sendable {
  private let bundle: Bundle
  private let preferredLanguages: [String]

  public init(
    bundle: Bundle? = nil,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) {
    self.bundle = bundle ?? .module
    self.preferredLanguages = preferredLanguages
  }

  public func string(_ key: String) -> String {
    let localizationBundle = localizedBundle() ?? bundle
    return NSLocalizedString(
      key,
      tableName: "Localizable",
      bundle: localizationBundle,
      value: key,
      comment: ""
    )
  }

  public func string(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: string(key), locale: Locale.current, arguments: arguments)
  }

  private func localizedBundle() -> Bundle? {
    let localizations = bundle.localizations.filter { $0 != "Base" }
    let preferred = Bundle.preferredLocalizations(
      from: localizations,
      forPreferences: preferredLanguages
    )
    guard let language = preferred.first,
          let path = bundle.path(forResource: language, ofType: "lproj") else {
      return nil
    }
    return Bundle(path: path)
  }
}

public enum L10n {
  public static func string(_ key: String) -> String {
    Localization().string(key)
  }

  public static func string(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: Localization().string(key), locale: Locale.current, arguments: arguments)
  }
}
