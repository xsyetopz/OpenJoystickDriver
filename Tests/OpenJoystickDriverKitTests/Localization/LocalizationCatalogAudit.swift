import Foundation

@testable import OpenJoystickDriverKit

enum LocalizationCatalogAudit {
  static let nonLinguisticSourceIdenticalKeys: Set<String> = [
    "app.name", "controller.dualSense", "controller.dualShock3", "controller.dualShock4",
    "controller.flydigi", "controller.genericHID", "controller.originalXbox",
    "controller.standardHID", "controller.steamController", "controller.switchPro",
    "controller.switchProController", "controller.xbox360", "controller.xbox360Wireless",
    "controller.xbox360WirelessDeveloper", "controller.xboxOne", "controller.xboxOriginal",
    "controllers.usbIdentifier", "developer.hid", "developer.usbID", "inputTest.yTriangle",
    "mapping.buttonNorth", "mapping.dpadDirection", "mapping.paddle1", "mapping.paddle2",
    "mapping.paddle3", "mapping.paddle4", "menu.projectPage", "profiles.sectionDpad",
  ]

  private static let spanishTerms: Set<String> = [
    "developer.packetColumnBytes", "inputTest.color", "keyboard.control", "profiles.controlNumber",
    "profiles.motion.local",
    "profiles.physical.motor", "profiles.stick.horizontal", "profiles.stick.vertical",
    "profiles.trackball.enabled", "profiles.turbo", "settings.general",
  ]
  private static let frenchTerms: Set<String> = [
    "capture.destination", "capture.gain", "cli.controller.show.label.session",
    "cli.status.label.extension", "cli.status.label.service", "common.destination",
    "common.service", "console.title", "inputTest.menu", "keyboard.option", "mapping.guide",
    "mapping.mode", "mapping.options", "mapping.start", "motion.calibration.pause",
    "profiles.activationMode", "profiles.motion.local", "profiles.sectionSticks",
    "profiles.stick.horizontal", "profiles.stick.source", "profiles.stick.vertical",
    "profiles.touch.surface", "profiles.trackball.enabled", "profiles.turbo",
    "settings.notifications", "settings.service",
  ]

  private static let sourceIdenticalTermsByLocale: [String: Set<String>] = [
    "ar-SA": [
      "keyboard.command", "keyboard.control", "keyboard.escape", "keyboard.option",
      "keyboard.return", "keyboard.shift", "keyboard.tab",
    ],
    "de-DE": [
      "capture.controller", "capture.linear", "cli.access.status.socket",
      "cli.controller.show.label.name", "common.controller", "common.status", "console.stream",
      "controllers.label", "developer.controller", "developer.controllerDetails",
      "developer.route", "inputTest.home", "keyboard.control", "keyboard.escape", "mapping.guide",
      "mapping.start", "profiles.physical.motor", "profiles.sectionSticks",
      "profiles.stick.horizontal", "profiles.stick.source", "profiles.trackball.enabled",
      "profiles.trigger.source", "profiles.turbo", "settings.status", "settings.updates",
      "shortcuts.controller.name", "shortcuts.controller.type", "shortcuts.parameter.controller",
      "shortcuts.profile.name",
    ],
    "es-ES": spanishTerms.union(["menu.zoom"]),
    "es-MX": spanishTerms,
    "fr-CA": frenchTerms.union(["developer.packetColumnDirection"]),
    "fr-FR": frenchTerms,
    "hi-IN": ["keyboard.escape", "keyboard.return"],
    "it-IT": [
      "capture.controller", "cli.access.status.socket", "cli.controller.show.label.input",
      "cli.controller.show.label.record", "common.controller", "console.output", "console.title",
      "controllers.label", "debug.title", "developer.controller", "developer.controllerDetails",
      "inputTest.home", "inputTest.menu", "inputTest.tabInput", "inputTest.tabOutput",
      "mapping.start", "menu.zoom", "motion.calibration.offset", "profiles.sectionTouch",
      "profiles.trackball.enabled", "profiles.turbo", "settings.debug",
      "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "ja-JP": [
      "keyboard.capsLock", "keyboard.escape", "keyboard.option", "keyboard.return",
      "keyboard.shift",
    ],
    "ko-KR": [
      "keyboard.capsLock", "keyboard.command", "keyboard.control", "keyboard.escape",
      "keyboard.option", "keyboard.return", "keyboard.shift",
    ],
    "nl-NL": [
      "capture.controller", "cli.access.status.socket", "cli.controller.show.label.protocol",
      "cli.controller.show.label.record", "cli.controller.show.label.rumble",
      "cli.status.label.controllers", "cli.status.label.service", "common.controller",
      "common.controllers", "common.protocol", "common.runtime", "common.service", "common.status",
      "common.stop", "console.stream", "console.title", "controllers.label", "controllers.protocol",
      "controllers.title", "debug.controllers", "debug.runtime", "developer.controller",
      "developer.controllerDetails", "developer.packetColumnBytes", "developer.route",
      "inputTest.home", "inputTest.menu", "inputTest.rumble", "keyboard.capsLock",
      "keyboard.command", "keyboard.control",
      "keyboard.escape", "keyboard.option", "keyboard.return", "keyboard.shift", "keyboard.tab",
      "mapping.guide", "mapping.physicalRumble", "mapping.start", "menu.help", "menu.zoom",
      "motion.calibration.offset", "profiles.activator", "profiles.physical.effect",
      "profiles.physical.motor", "profiles.sectionSticks", "profiles.sectionTriggers",
      "profiles.stick.source", "profiles.trackball.enabled", "profiles.trigger.source",
      "profiles.turbo", "settings.controllerCount", "settings.controllers", "settings.runtime",
      "settings.service", "settings.status", "settings.updates", "shortcuts.controller.model",
      "shortcuts.controller.type", "shortcuts.parameter.controller",
    ],
    "pt-BR": [
      "capture.linear", "common.status", "console.title", "developer.packetColumnBytes",
      "inputTest.menu", "keyboard.control",
      "menu.zoom",
      "profiles.motion.local", "profiles.physical.motor", "profiles.stick.horizontal",
      "profiles.stick.vertical", "profiles.trackball.enabled", "profiles.turbo", "settings.status",
    ],
    "ru-RU": [
      "keyboard.capsLock", "keyboard.command", "keyboard.control", "keyboard.delete",
      "keyboard.escape", "keyboard.option", "keyboard.return", "keyboard.shift", "keyboard.tab",
      "mapping.guide",
    ],
    "tr-TR": [
      "keyboard.control", "keyboard.escape", "keyboard.option", "keyboard.return", "keyboard.shift",
      "keyboard.tab", "profiles.physical.motor", "profiles.trackball.enabled", "profiles.turbo",
      "shortcuts.controller.model",
    ],
    "vi-VN": [
      "cli.access.status.socket", "inputTest.home", "inputTest.menu", "keyboard.capsLock",
      "keyboard.command", "keyboard.control", "keyboard.delete", "keyboard.escape",
      "keyboard.option", "keyboard.pageDown", "keyboard.pageUp", "keyboard.return",
      "keyboard.shift", "keyboard.tab", "mapping.guide", "profiles.trackball.enabled",
      "profiles.turbo",
    ],
    "zh-CN": ["keyboard.option", "keyboard.shift"],
    "zh-TW": ["keyboard.escape", "keyboard.option"],
  ]

  static func allowedSourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let terms =
      sourceIdenticalTermsByLocale.first {
        $0.key.caseInsensitiveCompare(localization) == .orderedSame
      }?.value ?? []
    return nonLinguisticSourceIdenticalKeys.union(terms)
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

  /// Source texts that one word may translate in any language.
  private static let sharedTranslationSourceGroups: [Set<String>] = [
    ["deactivated", "disabled", "off"], ["delete", "remove", "uninstall"],
  ]

  /// Keys whose value starts like a subtitle line (`- Yes.`) where the source has no `-` token.
  static func dialogueDashKeys(for localization: String) -> Set<String> {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    return Set(
      localizedStrings.compactMap { key, value in
        guard value.range(of: #"^\s*[-–—]\s"#, options: .regularExpression) != nil,
          let source = sourceStrings[key],
          source.range(of: #"(^|\s)-(\s|$)"#, options: .regularExpression) == nil
        else { return nil }
        return key
      }
    )
  }

  /// Values shared by three or more different source texts, the shape of a copy-paste error.
  static func sharedValueCollisions(for localization: String) -> [String: Set<String>] {
    let sourceStrings = stringsData(for: Localization.sourceLocalization).map(parseStrings) ?? [:]
    let localizedStrings = stringsData(for: localization).map(parseStrings) ?? [:]
    let keysByValue = Dictionary(grouping: localizedStrings.keys) { localizedStrings[$0] ?? "" }
    return keysByValue.filter { _, keys in
      let sources = Set(keys.compactMap { sourceStrings[$0].map(normalizedSource) })
      return sources.count >= 3
        && !sharedTranslationSourceGroups.contains { sources.isSubset(of: $0) }
    }.mapValues(Set.init)
  }

  private static func normalizedSource(_ value: String) -> String {
    value.replacingOccurrences(of: #"[.…:]+$"#, with: "", options: .regularExpression).lowercased()
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
