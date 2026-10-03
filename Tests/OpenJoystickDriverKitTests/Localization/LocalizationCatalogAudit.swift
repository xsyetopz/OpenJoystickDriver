import Foundation

@testable import OpenJoystickDriverKit

enum LocalizationCatalogAudit {
  static let nonLinguisticSourceIdenticalKeys: Set<String> = [
    "app.name", "controller.dualSense", "controller.dualShock3", "controller.dualShock4",
    "controller.flydigi", "controller.genericHID", "controller.originalXbox",
    "controller.standardHID", "controller.steamController", "controller.switchPro",
    "controller.switchProController", "controller.xbox360", "controller.xbox360Wireless",
    "controller.xbox360WirelessDeveloper", "controller.xboxOne", "controller.xboxOriginal",
    "controllers.usbIdentifier", "developer.hid", "developer.usbID", "inputTest.aCross",
    "inputTest.yTriangle", "mapping.buttonNorth", "mapping.buttonSouth", "mapping.dpadDirection",
    "mapping.paddle1", "mapping.paddle2", "mapping.paddle3", "mapping.paddle4",
    "mapping.rightJoyConSL", "menu.projectPage", "profiles.sectionDpad",
    "setup.driverAccessibility", "setup.driverTitle",
  ]

  private static let sourceIdenticalTermsByLocale: [String: Set<String>] = [
    "af-ZA": [
      "cli.controller.show.label.battery", "settings.status", "controllers.battery",
      "profiles.turbo", "common.status", "common.stop", "keyboard.tab", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "ca-AD": [
      "cli.controller.show.label.controls", "cli.controller.show.label.protocol", "menu.zoom",
      "settings.general", "controllers.protocol", "profiles.controlNumber", "profiles.turbo",
      "mapping.mode", "common.protocol", "inputTest.color", "inputTest.rumble", "keyboard.control",
      "console.errors", "profiles.motion.local", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "ca-ES": [
      "cli.controller.show.label.controls", "cli.controller.show.label.protocol", "menu.zoom",
      "settings.general", "controllers.protocol", "profiles.controlNumber", "profiles.turbo",
      "mapping.mode", "common.protocol", "inputTest.color", "inputTest.rumble", "keyboard.control",
      "console.errors", "profiles.motion.local", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "ca-FR": [
      "cli.controller.show.label.controls", "cli.controller.show.label.protocol", "menu.zoom",
      "settings.general", "controllers.protocol", "profiles.controlNumber", "profiles.turbo",
      "mapping.mode", "common.protocol", "inputTest.color", "inputTest.rumble", "keyboard.control",
      "console.errors", "profiles.motion.local", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "ca-IT": [
      "cli.controller.show.label.controls", "cli.controller.show.label.protocol", "menu.zoom",
      "settings.general", "controllers.protocol", "profiles.controlNumber", "profiles.turbo",
      "mapping.mode", "common.protocol", "inputTest.color", "inputTest.rumble", "keyboard.control",
      "console.errors", "profiles.motion.local", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "cs-CZ": [
      "profiles.turbo", "profiles.trackball.enabled", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "da-DK": [
      "cli.controller.show.label.input", "cli.controller.show.label.session", "menu.zoom",
      "settings.status", "capture.destination", "profiles.turbo", "mapping.start",
      "profiles.touch.pointer", "common.status", "common.destination", "inputTest.rumble",
      "inputTest.testRumble", "motion.calibration.pause", "profiles.stick.pointerRing",
      "profiles.physical.motor",
      "shortcuts.controller.model", "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "de-AT": [
      "cli.controller.show.label.name", "settings.status", "capture.linear", "profiles.turbo",
      "common.status", "developer.route", "profiles.trackball.enabled", "profiles.physical.motor",
      "shortcuts.controller.name", "shortcuts.controller.type", "shortcuts.parameter.controller",
      "shortcuts.profile.name",
    ],
    "de-CH": [
      "cli.controller.show.label.name", "settings.status", "capture.linear", "profiles.turbo",
      "common.status", "developer.route", "profiles.trackball.enabled", "profiles.physical.motor",
      "shortcuts.controller.name", "shortcuts.controller.type", "shortcuts.parameter.controller",
      "shortcuts.profile.name",
    ],
    "de-DE": [
      "cli.controller.show.label.name", "settings.status", "capture.linear", "profiles.turbo",
      "common.status", "developer.route", "profiles.trackball.enabled", "profiles.physical.motor",
      "shortcuts.controller.name", "shortcuts.controller.type", "shortcuts.parameter.controller",
      "shortcuts.profile.name",
    ], "es-AR": ["profiles.turbo"], "es-CR": ["profiles.turbo"], "es-ES": ["profiles.turbo"],
    "es-MX": ["profiles.turbo"], "et-EE": ["profiles.turbo"], "fi-FI": ["profiles.turbo"],
    "fr-BE": [
      "cli.controller.show.label.session", "cli.status.label.extension", "cli.status.label.service",
      "settings.service", "capture.destination", "profiles.activationMode",
      "profiles.touch.surface", "common.service", "common.destination", "console.title",
      "motion.calibration.pause",
    ],
    "fr-CA": [
      "cli.controller.show.label.session", "cli.status.label.extension", "cli.status.label.service",
      "settings.service", "capture.destination", "profiles.activationMode",
      "profiles.touch.surface", "common.service", "common.destination", "console.title",
      "motion.calibration.pause",
    ],
    "fr-CH": [
      "cli.controller.show.label.session", "cli.status.label.extension", "cli.status.label.service",
      "settings.service", "capture.destination", "profiles.activationMode",
      "profiles.touch.surface", "common.service", "common.destination", "console.title",
      "motion.calibration.pause",
    ],
    "fr-FR": [
      "cli.controller.show.label.session", "cli.status.label.extension", "cli.status.label.service",
      "settings.service", "capture.destination", "profiles.activationMode",
      "profiles.touch.surface", "common.service", "common.destination", "console.title",
      "motion.calibration.pause",
    ], "ga-IE": ["profiles.turbo", "common.stop", "profiles.trackball.yaw"],
    "hr-HR": [
      "profiles.turbo", "inputTest.testRumble", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "hu-HU": ["profiles.trackball.yaw", "profiles.physical.motor"],
    "it-CH": [
      "cli.controller.show.label.record", "menu.zoom", "settings.debug", "profiles.turbo",
      "debug.title",
      "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "it-IT": [
      "cli.controller.show.label.input", "cli.controller.show.label.record", "menu.zoom",
      "settings.debug", "profiles.turbo", "debug.title",
      "shortcuts.controller.type", "shortcuts.parameter.controller",
    ], "lt-LT": ["profiles.turbo"], "lv-LV": ["profiles.turbo"],
    "nb-NO": [
      "menu.zoom", "settings.status", "profiles.turbo", "mapping.start", "common.status",
      "inputTest.rumble", "inputTest.testRumble", "motion.calibration.pause",
      "profiles.physical.motor",
    ],
    "nl-BE": [
      "cli.controller.show.label.protocol", "cli.controller.show.label.record",
      "cli.status.label.controllers", "settings.status",
      "settings.updates", "controllers.protocol", "profiles.activator", "profiles.sectionTriggers",
      "common.status", "common.protocol", "keyboard.tab", "console.title",
      "motion.calibration.offset", "profiles.trackball.enabled", "profiles.trigger.source",
      "shortcuts.controller.model", "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "nl-NL": [
      "cli.controller.show.label.protocol", "cli.controller.show.label.record",
      "cli.status.label.controllers", "settings.status",
      "settings.updates", "controllers.protocol", "profiles.activator", "profiles.sectionTriggers",
      "common.status", "common.protocol", "keyboard.tab", "console.title",
      "motion.calibration.offset", "profiles.trackball.enabled", "profiles.trigger.source",
      "shortcuts.controller.model", "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "nn-NO": [
      "menu.zoom", "profiles.turbo", "inputTest.rumble", "inputTest.testRumble",
      "motion.calibration.offset", "motion.calibration.pause", "profiles.physical.motor",
    ],
    "no-NO": [
      "menu.zoom", "settings.status", "profiles.turbo", "mapping.start", "common.status",
      "inputTest.rumble", "inputTest.testRumble", "motion.calibration.pause",
      "profiles.physical.motor",
    ], "pl-PL": ["profiles.turbo", "inputTest.menu", "shortcuts.controller.model"],
    "pt-BR": ["menu.zoom", "profiles.turbo", "keyboard.capsLock", "profiles.physical.motor"],
    "pt-PT": ["menu.zoom", "profiles.turbo", "keyboard.capsLock", "profiles.physical.motor"],
    "ro-RO": [
      "cli.controller.show.label.protocol", "menu.zoom", "profiles.activator", "profiles.turbo",
      "inputTest.testRumble", "profiles.motion.local", "profiles.trigger.source",
      "profiles.physical.motor",
      "shortcuts.controller.model", "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "se-FI": [
      "menu.zoom", "profiles.turbo", "inputTest.rumble", "keyboard.capsLock", "keyboard.tab",
      "motion.calibration.offset",
    ],
    "se-NO": [
      "menu.zoom", "profiles.turbo", "inputTest.rumble", "keyboard.capsLock", "keyboard.tab",
      "motion.calibration.offset",
    ],
    "sk-SK": [
      "profiles.turbo", "profiles.trackball.enabled", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "sl-SI": [
      "profiles.turbo", "inputTest.testRumble", "profiles.physical.motor",
      "shortcuts.controller.model",
    ],
    "sv-FI": [
      "cli.controller.show.label.session", "settings.status", "profiles.turbo", "common.status",
      "inputTest.rumble", "profiles.physical.motor",
    ],
    "sv-SE": [
      "cli.controller.show.label.session", "settings.status", "profiles.turbo", "common.status",
      "inputTest.rumble", "profiles.physical.motor",
    ],
    "sr-YU": ["shortcuts.controller.model"], "tr-TR": ["shortcuts.controller.model"],
  ]

  /// macOS ships no localization for these languages, so System Settings shows its English pane
  /// and permission names, and the CLI names them the way the user sees them.
  private static let englishSystemSettingsPanes: Set<String> = [
    "cli.permission.pane.accessibility", "cli.permission.pane.driver_extension",
    "cli.permission.pane.input_monitoring",
  ]
  private static let englishSystemSettingsNames: Set<String> = [
    "cli.permission.name.accessibility", "cli.permission.name.input_monitoring",
  ]
  private static let englishSystemSettingsTermsByLocale: [String: Set<String>] = [
    "af-ZA": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    // The app already names both permissions in Amharic; only the pane paths stay English.
    "am-ET": englishSystemSettingsPanes,
    "et-EE": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "eu-ES": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "ga-IE": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "lt-LT": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "lv-LV": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "se-FI": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "se-NO": englishSystemSettingsPanes.union(englishSystemSettingsNames),
    "sl-SI": englishSystemSettingsPanes.union(englishSystemSettingsNames),
  ]

  static func allowedSourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    func terms(in table: [String: Set<String>]) -> Set<String> {
      table.first { $0.key.caseInsensitiveCompare(localization) == .orderedSame }?.value ?? []
    }
    return nonLinguisticSourceIdenticalKeys.union(terms(in: sourceIdenticalTermsByLocale)).union(
      terms(in: englishSystemSettingsTermsByLocale)
    )
  }

  static func keys(for localization: String) -> Set<String> {
    var result = stringsData(for: localization).map { Set(parseStrings($0).keys) } ?? []
    result.formUnion(stringsDictionary(for: localization).keys)
    return result
  }

  static func placeholderSignatures(for localization: String) -> [String: [String]] {
    var result =
      stringsData(for: localization).map {
        parseStrings($0).mapValues { placeholderSignature(in: $0) }
      } ?? [:]
    for (key, value) in stringsDictionary(for: localization) {
      var strings: [String] = []
      collectPluralStrings(value, into: &strings)
      result[key] = strings.flatMap { placeholderSignature(in: $0) }.sorted()
    }
    return result
  }

  static func pluralCategories(for localization: String) -> [String: Set<String>] {
    stringsDictionary(for: localization).mapValues(collectPluralCategories)
  }

  static func sourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    var result: Set<String> = Set(
      localizedStrings.compactMap { key, value in
        guard sourceStrings[key] == value, isEnglishProse(value) else { return nil }
        return key
      }
    )

    let sourcePlurals = stringsDictionary(for: Localization.sourceLocalization)
    let localizedPlurals = stringsDictionary(for: localization)
    for (key, localizedValue) in localizedPlurals {
      guard let sourceValue = sourcePlurals[key] else { continue }
      var sourceValues: [String] = []
      var localizedValues: [String] = []
      collectPluralStrings(sourceValue, into: &sourceValues)
      collectPluralStrings(localizedValue, into: &localizedValues)
      if zip(sourceValues, localizedValues).contains(where: { source, localized in
        source == localized && isEnglishProse(source)
      }) {
        result.insert(key)
      }
    }
    return result
  }

  private static func resourceData(for localization: String, extension: String) -> Data? {
    guard
      let path = Localization.moduleBundle.path(
        forResource: "Localizable",
        ofType: `extension`,
        inDirectory: "\(localization).lproj"
      )
    else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }

  private static func stringsData(for localization: String) -> Data? {
    resourceData(for: localization, extension: "strings")
  }

  private static func stringsDictionary(for localization: String) -> [String: Any] {
    guard let data = resourceData(for: localization, extension: "stringsdict"),
      let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = value as? [String: Any]
    else { return [:] }
    return dictionary
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
      result[String(text[keyRange])] = String(text[valueRange])
    }
    return result
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

  private static func placeholderSignature(in value: String) -> [String] {
    let pattern = #"%(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z]"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.matches(in: value, range: range).compactMap { match in
      Range(match.range, in: value).map { String(value[$0]) }
    }
  }

  private static func isEnglishProse(_ value: String) -> Bool {
    let withoutPlaceholders = value.replacingOccurrences(
      of: #"%(?:#@\w+@|(?:[0-9]+\$)?[-+0-9.#]*[@a-zA-Z])"#,
      with: "",
      options: .regularExpression
    )
    return withoutPlaceholders.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil
  }
}
