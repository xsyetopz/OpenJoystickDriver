import Foundation

@testable import OpenJoystickDriverKit

enum LocalizationCatalogAudit {
  /// Brand, product and technical names that every language writes as `en-US` does: a test
  /// requires each to equal `en-US` in every locale.
  static let sameInEveryLocaleKeys: Set<String> = [
    "term.protocolFamily.nintendoSwitch1", "term.protocolFamily.nintendoSwitch2",
    "term.protocolFamily.nintendoWii",
    "term.protocolFamily.sonyDualSense", "term.protocolFamily.sonyDualShock4",
    "term.protocolFamily.sonySixaxis", "term.protocolFamily.valveSteamController",
    "term.protocolFamily.valveSteamDeck", "term.protocolFamily.valveSteamTriton",
    "term.protocolFamily.vendorFlydigi", "term.protocolFamily.vendorGameSir",
    "term.protocolFamily.vendorNvidiaShield", "term.protocolFamily.xboxGip",
    "term.protocolFamily.xboxXid", "term.protocolFamily.xboxXusb",
    "term.protocolVariant.usb",
    "cli.controller.show.labelMotionPlus", "term.wiiExtension.nunchuk",
    "term.wiiExtension.classicController", "term.wiiExtension.classicControllerPro",
    "term.wiiExtension.motionPlus",
    "platform.macos.ui.controllers.server.system", "ui.controllers.server.ojd",
  ]

  static let nonLinguisticSourceIdenticalKeys: Set<String> = sameInEveryLocaleKeys.union([
    "term.app.name",
    // Bluetooth LE as the system writes it; Korean and Chinese write Bluetooth in their script.
    "term.protocolVariant.bluetoothLe",
    "ui.controllers.usbIdentifier", "ui.controllers.discovery.hid", "ui.developer.hid",
    "ui.developer.usbID",
    "ui.inputTest.yTriangle",
    "ui.mapping.buttonNorth", "ui.mapping.dpadDirection", "ui.menu.projectPage",
    "ui.profiles.sectionDpad",
    "ui.access.transport.web", "ui.access.web", "ui.profiles.system.url",
  ])

  private static let spanishTerms: Set<String> = [
    "ui.developer.packetColumnBytes", "ui.inputTest.color", "term.key.control",
    "ui.profiles.controlNumber",
    "ui.profiles.motion.local",
    "ui.profiles.physical.motor", "ui.profiles.stick.horizontal", "ui.profiles.stick.vertical",
    "ui.profiles.trackball.enabled", "ui.profiles.turbo",
    "ui.library.mods", "ui.access.scope.control", "ui.access.socket", "ui.access.transport.socket",
    "ui.access.tokens", "ui.access.token.issued.title", "ui.access.token.named",
    "ui.settings.general.title", "ui.controllers.server.ojd", "term.macro", "ui.profiles.macros",
  ]
  private static let frenchTerms: Set<String> = [
    "ui.library.field.version",
    "ui.capture.gain",
    "cli.controller.show.labelSession", "cli.controller.show.labelExtension",
    "cli.status.group.labelTransportExtension", "cli.status.group.labelService", "term.destination",
    "ui.inputTest.menu", "term.key.alt", "ui.mapping.guide",
    "ui.mapping.start", "ui.motion.calibration.pause",
    "ui.profiles.activationMode", "ui.profiles.motion.local", "ui.profiles.sectionSticks",
    "ui.profiles.stick.horizontal", "ui.profiles.stick.source", "ui.profiles.stick.vertical",
    "ui.profiles.touch.surface", "ui.profiles.trackball.enabled", "ui.profiles.turbo",
    "ui.settings.notifications.notifications", "ui.settings.general.version",
    "ui.access.transport.socket", "ui.access.web.port",
    "ui.library.mods", "term.macro", "ui.profiles.macros",
  ]

  private static let sourceIdenticalTermsByLocale: [String: Set<String>] = [
    "ar-SA": [
      "term.key.meta", "term.key.control", "term.key.escape", "term.key.alt",
      "term.key.return", "term.key.shift", "term.key.tab",
    ],
    "de-DE": [
      "ui.shortcuts.action.removeMod.name", "term.parser", "term.protocolVariant.dongle",
      "ui.library.field.version", "ui.menu.controller.title", "ui.activity.filter",
      "ui.activity.column.details",
      "ui.access.details", "ui.library.details",
      "ui.access.token.name", "ui.access.web.port", "ui.access.web.enable.port", "ui.access.socket",
      "ui.access.transport.socket", "ui.access.token.issued.title", "ui.access.token.named",
      "ui.access.tokens", "ui.library.mods",
      "ui.capture.linear", "cli.access.status.socket",
      "cli.controller.show.labelName", "term.controller", "term.status",
      "ui.developer.controller", "ui.developer.controllerDetails", "ui.profiles.speak.text",
      "ui.developer.route", "ui.inputTest.home", "term.key.control", "term.key.escape",
      "ui.mapping.guide",
      "ui.mapping.start", "ui.profiles.physical.motor", "ui.profiles.sectionSticks",
      "ui.profiles.stick.horizontal", "ui.profiles.stick.source", "ui.profiles.trackball.enabled",
      "ui.profiles.trigger.source", "ui.profiles.turbo", "ui.settings.general.updates",
      "ui.settings.general.version", "ui.profiles.pointerSpeed.driverTrigger",
      "ui.shortcuts.controller.name", "ui.shortcuts.controller.type",
      "ui.shortcuts.parameter.controller",
      "ui.shortcuts.profile.name", "ui.profiles.sort.name", "ui.profiles.sort.controller",
      "ui.profiles.apps",
    ],
    "es-ES": spanishTerms.union(["ui.menu.window.zoom", "ui.shortcuts.action.light.color"]),
    "es-MX": spanishTerms.union(["ui.menu.window.zoom", "ui.shortcuts.action.light.color"]),
    "fr-CA": frenchTerms.union(["ui.developer.packetColumnDirection"]).union([
      "ui.activity.column.message",
      "ui.menu.app.services", "ui.menu.window.zoom", "ui.settings.notifications.title",
    ]),
    "fr-FR": frenchTerms.union([
      "ui.activity.column.message",
      "ui.menu.app.services", "ui.menu.window.zoom", "ui.settings.notifications.title",
    ]),
    "hi-IN": ["term.key.escape", "term.key.return"],
    "id-ID": [
      "ui.shortcuts.action.installMod.folder", "term.parser", "term.protocolVariant.dongle",
      "ui.library.layer.driver", "ui.access.token.issued.title", "ui.access.token.named",
      "ui.activity.filter", "ui.activity.mode.log",
      "ui.access.web.port", "ui.access.web.enable.port", "ui.menu.window.zoom",
      "ui.controllers.server.ojd",
      "cli.controller.show.labelInput", "cli.explain.group.area", "cli.explain.group.areaEndpoint",
      "term.status", "ui.console.output", "ui.developer.packetColumnData",
      "ui.inputTest.home", "ui.inputTest.menu",
      "term.key.capsLock", "term.key.meta",
      "term.key.control", "term.key.escape", "term.key.alt", "term.key.return", "term.key.shift",
      "term.key.tab", "ui.mapping.guide", "ui.motion.calibration.offset",
      "ui.profiles.physical.motor",
      "ui.profiles.stick.horizontal",
      "ui.profiles.target", "ui.profiles.trackball.enabled", "ui.profiles.turbo",
      "ui.shortcuts.controller.model", "ui.menu.file.title", "ui.menu.edit.title",
    ],
    "it-IT": [
      "term.macro", "ui.profiles.sort.controller",
      "term.parser", "term.protocolVariant.dongle",
      "ui.access.token.issued.title", "ui.access.token.named",
      "ui.menu.controller.title", "ui.menu.file.title", "ui.menu.window.zoom",
      "ui.access.socket", "ui.access.transport.socket",
      "cli.access.status.socket", "cli.controller.show.labelInput",
      "cli.controller.show.labelRecord", "cli.controller.show.inputMappingRecord",
      "term.controller",
      "ui.console.output",
      "ui.developer.controller", "ui.developer.controllerDetails",
      "ui.inputTest.home", "ui.inputTest.menu", "ui.mapping.start", "ui.motion.calibration.offset",
      "ui.profiles.sectionTouch",
      "ui.profiles.trackball.enabled", "ui.profiles.turbo", "ui.shortcuts.controller.type",
      "ui.shortcuts.parameter.controller",
    ],
    "ja-JP": [
      "term.key.capsLock", "term.key.escape", "term.key.alt", "term.key.return",
      "term.key.shift",
    ],
    "ko-KR": [
      "term.key.capsLock", "term.key.meta", "term.key.control", "term.key.escape",
      "term.key.alt", "term.key.return", "term.key.shift",
    ],
    "nl-NL": [
      "term.macro", "ui.profiles.sort.controller",
      "term.parser", "term.protocolVariant.dongle",
      "ui.access.details", "ui.library.details", "ui.activity.filter",
      "ui.activity.column.details",
      "ui.access.token.issued.title", "ui.access.token.named", "ui.access.tokens",
      "ui.library.mods",
      "ui.menu.window.zoom",
      "ui.sidebar.controllers.title",
      "ui.menu.controller.title", "ui.menu.help.title",
      "ui.access.socket", "ui.access.transport.socket",
      "cli.access.status.socket", "cli.controller.show.labelProtocol",
      "cli.controller.show.labelRecord", "cli.controller.show.inputMappingRecord",
      "cli.controller.show.labelRumble",
      "cli.status.group.labelControllers", "cli.status.group.labelService", "term.controller",
      "term.protocol", "term.status",
      "action.stop", "ui.developer.controller",
      "ui.developer.controllerDetails", "ui.developer.packetColumnBytes", "ui.developer.route",
      "ui.inputTest.home", "ui.inputTest.menu", "ui.inputTest.rumble", "term.key.capsLock",
      "term.key.meta", "term.key.control",
      "term.key.escape", "term.key.alt", "term.key.return", "term.key.shift", "term.key.tab",
      "ui.mapping.guide", "ui.mapping.physicalRumble", "ui.mapping.start",
      "ui.motion.calibration.offset",
      "ui.profiles.activator", "ui.profiles.physical.effect",
      "ui.profiles.physical.motor", "ui.profiles.sectionSticks", "ui.profiles.sectionTriggers",
      "ui.profiles.stick.source", "ui.profiles.trackball.enabled", "ui.profiles.trigger.source",
      "ui.profiles.turbo", "ui.settings.general.controllers", "ui.settings.general.updates",
      "ui.shortcuts.controller.model",
      "ui.shortcuts.controller.type", "ui.shortcuts.parameter.controller",
      "ui.profiles.pointerSpeed.driverTrigger",
    ],
    "pt-BR": [
      "term.macro", "ui.profiles.macros",
      "term.parser",
      "ui.activity.mode.log",
      "ui.access.token.issued.title", "ui.access.token.named",
      "ui.access.tokens", "ui.library.mods",
      "ui.menu.window.zoom",
      "ui.capture.linear", "term.status", "ui.developer.packetColumnBytes",
      "ui.inputTest.menu", "term.key.control",
      "ui.profiles.motion.local", "ui.profiles.physical.motor", "ui.profiles.stick.horizontal",
      "ui.profiles.stick.vertical", "ui.profiles.trackball.enabled", "ui.profiles.turbo",
      "ui.controllers.server.ojd",
    ],
    "ru-RU": [
      "term.key.capsLock", "term.key.meta", "term.key.control", "term.key.delete",
      "term.key.escape", "term.key.alt", "term.key.return", "term.key.shift", "term.key.tab",
      "ui.mapping.guide",
    ],
    "th-TH": [
      "ui.inputTest.home", "term.key.capsLock", "term.key.meta", "term.key.control",
      "term.key.delete", "term.key.escape", "term.key.forwardDelete", "term.key.alt",
      "term.key.pageDown", "term.key.pageUp", "term.key.return", "term.key.shift",
      "term.key.space", "term.key.tab",
    ],
    "tr-TR": [
      "term.key.control", "term.key.escape", "term.key.alt", "term.key.return", "term.key.shift",
      "term.key.tab", "ui.profiles.physical.motor", "ui.profiles.trackball.enabled",
      "ui.profiles.turbo",
      "ui.shortcuts.controller.model",
    ],
    "vi-VN": [
      "term.macro",
      "ui.access.socket", "ui.access.transport.socket",
      "cli.access.status.socket", "ui.inputTest.home", "ui.inputTest.menu", "term.key.capsLock",
      "term.key.meta", "term.key.control", "term.key.delete", "term.key.escape",
      "term.key.alt", "term.key.pageDown", "term.key.pageUp", "term.key.return",
      "term.key.shift", "term.key.tab", "ui.mapping.guide", "ui.profiles.trackball.enabled",
      "ui.profiles.turbo", "ui.access.token.issued.title", "ui.access.token.named",
    ],
    "zh-CN": ["term.key.alt", "term.key.shift"],
    "zh-TW": ["term.key.escape", "term.key.alt"],
  ]

  static func allowedSourceIdenticalEnglishProseKeys(for localization: String) -> Set<String> {
    let terms =
      sourceIdenticalTermsByLocale.first {
        $0.key.caseInsensitiveCompare(localization) == .orderedSame
      }?.value ?? []
    return nonLinguisticSourceIdenticalKeys.union(terms)
  }

  /// The `.strings` values of `localization`, by key.
  static func values(for localization: String) -> [String: String] {
    stringsData(for: localization).map(parseStrings) ?? [:]
  }

  static func keys(for localization: String) -> Set<String> {
    var result = stringsData(for: localization).map { Set(parseStrings($0).keys) } ?? []
    result.formUnion(stringsDictionary(for: localization).keys)
    return result
  }

  /// The format specifiers of each key, in sorted order: a translation may reorder its numbered
  /// specifiers.
  ///
  /// A `.stringsdict` entry lists each distinct specifier once, because a language carries only the
  /// plural categories it needs and every category repeats the same specifiers.
  static func placeholderSignatures(for localization: String) -> [String: [String]] {
    var result =
      stringsData(for: localization).map {
        parseStrings($0).mapValues { placeholderSignature(in: $0).sorted() }
      } ?? [:]
    for (key, value) in stringsDictionary(for: localization) {
      var strings: [String] = []
      collectPluralStrings(value, into: &strings)
      result[key] = Set(strings.flatMap { placeholderSignature(in: $0) }).sorted()
    }
    return result
  }

  /// The problems of the `.stringsdict` entries of `localization` against the plural categories
  /// its language needs.
  static func pluralCategoryProblems(
    for localization: String,
    required: Set<String>
  ) -> [String] {
    let entries = stringsDictionary(for: localization)
    guard !entries.isEmpty else { return ["no .stringsdict entry"] }
    return pluralCategoryProblems(in: entries, required: required)
  }

  /// The problems of `entries`: an entry with no plural variable, and a plural variable that lacks
  /// a category of `required`.
  ///
  /// Each variable needs every category on its own.
  static func pluralCategoryProblems(in entries: [String: Any], required: Set<String>) -> [String] {
    var problems: [String] = []
    for (key, entry) in entries.sorted(by: { $0.key < $1.key }) {
      let variables = pluralVariables(entry)
      if variables.isEmpty {
        problems.append("\(key) has no plural variable")
      }
      for (name, present) in variables.sorted(by: { $0.key < $1.key })
      where !required.isSubset(of: present) {
        problems.append("\(key): \(name) lacks \(required.subtracting(present).sorted())")
      }
    }
    return problems
  }

  /// The keys whose `.strings` value takes a count (`%#@name@`) but that have no `.stringsdict`
  /// entry in the same bundle.
  static func countKeysWithoutPluralEntry(for localization: String) -> [String] {
    countKeysWithoutPluralEntry(
      strings: values(for: localization),
      entries: stringsDictionary(for: localization)
    )
  }

  static func countKeysWithoutPluralEntry(
    strings: [String: String],
    entries: [String: Any]
  ) -> [String] {
    strings.filter { key, value in
      value.range(of: #"%#@[A-Za-z0-9_]+@"#, options: .regularExpression) != nil
        && entries[key] == nil
    }.keys.sorted()
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

  /// Keys whose source value reports work in progress: its last sentence, or the sentence before an
  /// instruction that starts with a capital letter, ends in `...`.
  static func inProgressSourceKeys() -> [String] {
    values(for: Localization.sourceLocalization).filter { _, value in
      value.range(of: #"\.\.\.(?= [A-Z]|$)"#, options: .regularExpression) != nil
    }.keys.sorted()
  }

  /// Keys whose in-progress source text loses its ellipsis in `localization`.
  ///
  /// `C` keeps `...`, a translation writes `…`, and neither keeps an ASCII `...`. A source that
  /// ends in the ellipsis ends in it in the translation; a source with an instruction after it
  /// keeps text after it.
  static func lostEllipsisKeys(for localization: String) -> [String] {
    let source = values(for: Localization.sourceLocalization)
    let localized = values(for: localization)
    let isC = localization.caseInsensitiveCompare("C") == .orderedSame
    let mark = isC ? "..." : "…"
    return inProgressSourceKeys().filter { key in
      guard let sourceValue = source[key], let value = localized[key] else { return true }
      if isC { return value != sourceValue }
      guard !value.contains("..."), let range = value.range(of: mark) else { return true }
      return sourceValue.hasSuffix("...") != (range.upperBound == value.endIndex)
    }
  }

  /// Source texts that one word may translate in any language.
  private static let sharedTranslationSourceGroups: [Set<String>] = [
    ["deactivated", "disabled", "off"], ["delete", "remove", "uninstall"],
    ["close", "dismiss", "off", "turn off"],
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
      let value = try? unsafe PropertyListSerialization.propertyList(
        from: data,
        options: 0,
        format: nil
      ),
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
    unsafe expression.enumerateMatches(in: text, range: range) { match, _, _ in
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

  /// The plural variables inside `value`, each with the categories it defines, by variable path.
  private static func pluralVariables(_ value: Any, path: String = "") -> [String: Set<String>] {
    guard let dictionary = value as? [String: Any] else { return [:] }
    var variables: [String: Set<String>] = [:]
    for (name, child) in dictionary {
      guard let variable = child as? [String: Any] else { continue }
      let variablePath = path.isEmpty ? name : "\(path)/\(name)"
      if variable["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType" {
        variables[variablePath] = Set(variable.keys.filter { !$0.hasPrefix("NSString") })
      } else {
        variables.merge(pluralVariables(variable, path: variablePath)) { first, _ in first }
      }
    }
    return variables
  }

  static func placeholderSignature(in value: String) -> [String] {
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
