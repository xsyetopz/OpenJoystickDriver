import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LocalizationTests {
  @Test
  func packagesTheCompleteLocaleInventory() {
    let localizations = Localization.availableLocalizations()
    #expect(localizations.count == 22)
    let normalized = Set(localizations.map { $0.lowercased() })
    #expect(normalized.contains("en-us"))
    #expect(normalized.contains("ar-sa"))
    #expect(normalized.contains("zh-hk"))
    #expect(normalized.contains("c"))
  }

  @Test
  func everyLocaleHasTheSameCurrentCatalogShape() {
    let sourceKeys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    let sourcePlaceholders = LocalizationCatalogAudit.placeholderSignatures(
      for: Localization.sourceLocalization
    )
    #expect(!sourceKeys.isEmpty)
    #expect(sourceKeys.count == sourcePlaceholders.count)

    for locale in Localization.availableLocalizations() {
      #expect(LocalizationCatalogAudit.keys(for: locale) == sourceKeys)
      #expect(LocalizationCatalogAudit.placeholderSignatures(for: locale) == sourcePlaceholders)
    }
  }

  @Test
  func everyReasonForNotServingAControllerHasASentenceAndANextStepInEveryLocale() {
    for locale in Localization.availableLocalizations() {
      let keys = LocalizationCatalogAudit.keys(for: locale)
      for reason in ProtocolBindingReason.allCases {
        #expect(keys.contains(reason.explanationKey), "\(locale) has no \(reason.explanationKey)")
        #expect(keys.contains(reason.nextStepKey), "\(locale) has no \(reason.nextStepKey)")
      }
    }
  }

  @Test
  func everyNonEnglishLocaleTranslatesSourceEnglishProse() {
    let sourceKeys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    #expect(LocalizationCatalogAudit.nonLinguisticSourceIdenticalKeys.isSubset(of: sourceKeys))
    var usedNonLinguisticExceptions = Set<String>()

    for locale in Localization.availableLocalizations()
    where locale.caseInsensitiveCompare("C") != .orderedSame
      && !locale.lowercased().hasPrefix("en-")
    {
      let untranslated = LocalizationCatalogAudit.sourceIdenticalEnglishProseKeys(for: locale)
      let allowed = LocalizationCatalogAudit.allowedSourceIdenticalEnglishProseKeys(for: locale)
      #expect(
        untranslated.isSubset(of: allowed),
        "\(locale) leaves source English in \(untranslated.subtracting(allowed).sorted())"
      )
      #expect(
        allowed.subtracting(LocalizationCatalogAudit.nonLinguisticSourceIdenticalKeys).isSubset(
          of: untranslated
        ),
        "\(locale) has obsolete locale-specific exceptions"
      )
      usedNonLinguisticExceptions.formUnion(
        untranslated.intersection(LocalizationCatalogAudit.nonLinguisticSourceIdenticalKeys)
      )
    }

    #expect(
      usedNonLinguisticExceptions == LocalizationCatalogAudit.nonLinguisticSourceIdenticalKeys,
      "Non-linguistic exceptions must reference source-identical catalog entries"
    )
  }

  @Test
  func noLocaleUsesSubtitleLinesAsValues() {
    for locale in Localization.availableLocalizations() {
      let keys = LocalizationCatalogAudit.dialogueDashKeys(for: locale)
      #expect(keys.isEmpty, "\(locale) starts \(keys.sorted()) with a dialogue dash")
    }
  }

  @Test
  func differentSourceTextsKeepDifferentTranslations() {
    for locale in Localization.availableLocalizations() {
      let groups = LocalizationCatalogAudit.sharedValueCollisions(for: locale).values.map {
        $0.sorted()
      }
      #expect(groups.isEmpty, "\(locale) gives one value to \(groups.sorted { "\($0)" < "\($1)" })")
    }
  }

  @Test
  func inProgressTextsKeepTheirEllipsisInEveryLocale() {
    #expect(!LocalizationCatalogAudit.inProgressSourceKeys().isEmpty)
    for locale in Localization.availableLocalizations()
    where !locale.lowercased().hasPrefix("en-") {
      let keys = LocalizationCatalogAudit.lostEllipsisKeys(for: locale)
      #expect(keys.isEmpty, "\(locale) drops the ellipsis of \(keys)")
    }
  }

  @Test
  func packagedCatalogIncludesCLIAndInputTestProductKeys() {
    let keys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    for required in [
      "platform.macos.cli.root.group.abstract", "cli.shared.error.serviceUnavailable",
      "cli.service.start.abstract",
      "cli.status.group.labelControllers", "ui.inputTest.additionalButtons", "ui.inputTest.rumble",
      "ui.virtualProfile.title", "platform.macos.ui.setup.openSystemSettings",
      "ui.controllers.battery",
      "ui.controllers.chargingState", "ui.controllers.cableState", "ui.controllers.discharging",
      "ui.controllers.charging", "ui.controllers.batteryFull",
      "ui.controllers.batteryAccessibilityDetails",
      "ui.profiles.actions", "ui.profiles.editorSection", "ui.profiles.combinations",
    ] { #expect(keys.contains(required)) }
    #expect(keys.filter { $0.hasPrefix("ui.inputTest.") }.count >= 20)
  }

  @Test
  func eachPluralVariableCarriesTheCategoriesItsLanguageNeeds() {
    func variable(_ categories: [String]) -> [String: Any] {
      var result: [String: Any] = [
        "NSStringFormatSpecTypeKey": "NSStringPluralRuleType",
        "NSStringFormatValueTypeKey": "d",
      ]
      for category in categories { result[category] = "%d" }
      return result
    }
    let russian: Set<String> = ["one", "few", "many", "other"]
    // The categories of the two variables together are complete; neither variable is.
    let split: [String: Any] = [
      "files.moved": [
        "NSStringLocalizedFormatKey": "%#@files@ %#@folders@",
        "files": variable(["one", "few"]),
        "folders": variable(["many", "other"]),
      ]
    ]
    #expect(
      LocalizationCatalogAudit.pluralCategoryProblems(in: split, required: russian)
        == [
          "files.moved: files lacks [\"many\", \"other\"]",
          "files.moved: folders lacks [\"few\", \"one\"]",
        ]
    )
    let complete: [String: Any] = [
      "files.moved": [
        "NSStringLocalizedFormatKey": "%#@files@ %#@folders@",
        "files": variable(["one", "few", "many", "other"]),
        "folders": variable(["one", "few", "many", "other", "zero"]),
      ]
    ]
    #expect(
      LocalizationCatalogAudit.pluralCategoryProblems(in: complete, required: russian).isEmpty
    )
    #expect(
      LocalizationCatalogAudit.pluralCategoryProblems(
        in: ["files.none": ["NSStringLocalizedFormatKey": "none"]],
        required: russian
      ) == ["files.none has no plural variable"]
    )
  }

  @Test
  func aCountValueNeedsAStringsdictEntryOfTheSameKey() {
    let strings = [
      "files.moved": "%#@files@", "files.count": "%#@count@ files", "files.name": "%@",
    ]
    #expect(
      LocalizationCatalogAudit.countKeysWithoutPluralEntry(
        strings: strings,
        entries: ["files.count": [:]]
      ) == ["files.moved"]
    )
  }

  @Test
  func pluralResourcesCarryTheCategoriesEachLanguageNeeds() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Localization
      .deletingLastPathComponent()  // OpenJoystickDriverKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repository root
    let data = try Data(
      contentsOf: root.appendingPathComponent("Resources/Localization/PluralCategories.json")
    )
    let needed = try JSONDecoder().decode([String: Set<String>].self, from: data)
    let languages = Set(
      Localization.availableLocalizations().map { String($0.split(separator: "-")[0]) }
    )
    #expect(Set(needed.keys) == languages, "PluralCategories.json lists exactly the languages")
    for locale in Localization.availableLocalizations() {
      let language = String(locale.split(separator: "-")[0])
      let required = try #require(needed[language], "no plural categories for \(language)")
      let problems = LocalizationCatalogAudit.pluralCategoryProblems(
        for: locale,
        required: required
      )
      #expect(problems.isEmpty, "\(locale): \(problems)")
      #expect(
        LocalizationCatalogAudit.countKeysWithoutPluralEntry(for: locale).isEmpty,
        "\(locale) takes a count but has no stringsdict entry"
      )
    }

    let resolver = Localization(preferredLanguages: ["en-US"])
    #expect(
      resolver.plural(
        "status.controllerConnected",
        count: 1
      ) == "1 controller connected"
    )
    #expect(
      resolver.plural(
        "status.controllerConnected",
        count: 2
      ) == "2 controllers connected"
    )
    #expect(
      resolver.plural(
        "ui.debug.outputDevices",
        count: 0
      ) == "No controller output devices detected"
    )
  }

  @Test
  func countedTextPicksTheFormOfTheSelectedLanguage() {
    func text(_ language: String, _ key: String, _ arguments: CVarArg...) -> String {
      Localization(preferredLanguages: [language]).plural(key, arguments: arguments)
    }
    #expect(
      text("en-US", "ui.developer.hiddenIdlePackets", 1)
        == "Hidden 1 idle packet (still included in Export)."
    )
    #expect(
      text("en-US", "ui.developer.hiddenIdlePackets", 2)
        == "Hidden 2 idle packets (still included in Export)."
    )
    // The count is the second argument; the first is the selector text.
    #expect(
      text("en-US", "cli.profile.group.selectorAmbiguous", "work", 3)
        == "'work' names 3 profiles. Use one of these IDs:"
    )
    #expect(
      text("de-DE", "cli.controller.group.selectorAmbiguous", "pad", 1)
        == "„pad“ passt zu 1 Controller. Verwende eine dieser IDs:"
    )
    // The count is the third argument.
    #expect(
      text("en-US", "cli.record.test.mismatch", "A", "b.json", 1)
        == "The state that the parser of A produced differs from b.json in 1 field."
    )
    for (count, expected) in [
      (1, "пакет"), (2, "пакета"), (5, "пакетов"), (11, "пакетов"), (21, "пакет"), (22, "пакета"),
    ] {
      #expect(
        text("ru-RU", "ui.developer.stoppedPackets", count) == "Остановлено · \(count) \(expected)"
      )
    }
    for (count, expected) in [
      (1, "متوقف · حزمة واحدة"), (2, "متوقف · حزمتان"), (3, "متوقف · ٣ حزم"),
      (11, "متوقف · ١١ حزمة"),
    ] {
      #expect(text("ar-SA", "ui.developer.stoppedPackets", count) == expected)
    }
    #expect(text("ja-JP", "ui.developer.stoppedPackets", 1) == "停止 · 1 パケット")
    // French and Spanish write a million with "de": the `many` category.
    #expect(
      text("fr-FR", "cli.diagnose.group.sampleLimit", 1_000_000).contains("000 d’échantillons")
    )
    #expect(
      text("es-ES", "cli.diagnose.group.soakErrorTooManySamples", 1_000_000)
        == "El muestreo tomaría 1.000.000 de muestras. Aumente el intervalo de muestreo."
    )
  }

  @Test
  func connectedControllerCountsFollowThePluralRulesOfTheSelectedLanguage() {
    let english = Localization(preferredLanguages: ["en-US"])
    for (count, expected) in [
      (0, "0 controllers connected"), (1, "1 controller connected"),
      (2, "2 controllers connected"), (5, "5 controllers connected"),
      (21, "21 controllers connected"),
    ] {
      #expect(english.plural("status.controllerConnected", count: count) == expected)
    }
    let russian = Localization(preferredLanguages: ["ru-RU"])
    for (count, expected) in [
      (0, "0 контроллеров подключено"), (1, "1 контроллер подключён"),
      (2, "2 контроллера подключено"), (5, "5 контроллеров подключено"),
      (21, "21 контроллер подключён"),
    ] {
      #expect(russian.plural("status.controllerConnected", count: count) == expected)
    }
  }

  @Test
  func aPluralKeyWithoutAnEntryRendersTheKeyItself() {
    let english = Localization(preferredLanguages: ["en-US"])
    #expect(english.plural("missingPluralEntry", count: 3) == "missingPluralEntry")
  }

  @Test
  func preferredLanguageSelectionUsesTheLocaleCatalog() {
    let resolver = Localization(preferredLanguages: ["fr-FR", "en-US"])
    #expect(resolver.resolvedLanguage?.lowercased() == "fr-fr")
    #expect(resolver.string("action.refresh") == "Actualiser")

    #expect(resolver.string("test.missing.key") == "test.missing.key")
  }

  @Test
  func incompleteLocaleFallsBackToSourceEnglishResource() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriverLocalization-\(UUID().uuidString).bundle"
    )
    let resources = root.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Contents"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: resources.appendingPathComponent("en-US.lproj"),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: resources.appendingPathComponent("fr-FR.lproj"),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let info = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>CFBundleIdentifier</key>
      <string>test.localization</string></dict></plist>
      """
    try Data(info.utf8).write(to: root.appendingPathComponent("Contents/Info.plist"))
    try Data("\"shared\" = \"English source\";\n".utf8).write(
      to: resources.appendingPathComponent("en-US.lproj/Localizable.strings")
    )
    try Data("\"frOnly\" = \"French value\";\n".utf8).write(
      to: resources.appendingPathComponent("fr-FR.lproj/Localizable.strings")
    )

    let bundle = try #require(Bundle(path: root.path))
    let resolver = Localization(bundle: bundle, preferredLanguages: ["fr-FR"])
    #expect(resolver.resolvedLanguage == "fr-FR")
    #expect(resolver.string("frOnly") == "French value")
    #expect(resolver.string("shared") == "English source")
    #expect(resolver.string("missing") == "missing")
  }

  @Test
  func resolverCachesLocaleDiscoveryAtInitialization() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriverLocalizationCache-\(UUID().uuidString).bundle"
    )
    let resources = root.appendingPathComponent("Contents/Resources")
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Contents"),
      withIntermediateDirectories: true
    )
    for localization in ["en-US", "fr-FR"] {
      try FileManager.default.createDirectory(
        at: resources.appendingPathComponent("\(localization).lproj"),
        withIntermediateDirectories: true
      )
    }
    defer { try? FileManager.default.removeItem(at: root) }

    let info = """
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0"><dict><key>CFBundleIdentifier</key>
      <string>test.localization.cache</string></dict></plist>
      """
    try Data(info.utf8).write(to: root.appendingPathComponent("Contents/Info.plist"))

    let bundle = try #require(Bundle(path: root.path))
    let resolver = Localization(bundle: bundle, preferredLanguages: ["fr-FR"])
    try FileManager.default.createDirectory(
      at: resources.appendingPathComponent("de-DE.lproj"),
      withIntermediateDirectories: true
    )

    #expect(resolver.availableLocalizations == ["en-US", "fr-FR"])
    #expect(resolver.resolvedLanguage == "fr-FR")
    #expect(Localization.availableLocalizations(in: bundle) == ["de-DE", "en-US", "fr-FR"])
  }

  @Test
  func formattedValuesPreserveCatalogPlaceholders() {
    let resolver = Localization(preferredLanguages: ["en-US"])
    let value = resolver.plural(
      "status.controllerConnected",
      count: 3
    )
    #expect(value == "3 controllers connected")

    let area = resolver.formatted(
      "cli.explain.group.area",
      arguments: ["Endpoint" as CVarArg]
    )
    #expect(area == "Area: Endpoint")
  }

  @Test
  func everyProtocolFamilyHasOneDisplayNameKey() {
    let sourceKeys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    let familyKeys = Set(PhysicalProtocolID.allCases.map(\.displayNameKey))
    #expect(familyKeys.count == PhysicalProtocolID.allCases.count)
    #expect(familyKeys.isSubset(of: sourceKeys), "\(familyKeys.subtracting(sourceKeys).sorted())")
    let catalogFamilyKeys = sourceKeys.filter { $0.hasPrefix("term.protocolFamily.") }
    #expect(
      catalogFamilyKeys == familyKeys,
      "\(catalogFamilyKeys.subtracting(familyKeys).sorted())"
    )
    #expect(
      PhysicalProtocolID.sonyDualShock4.displayNameKey == "term.protocolFamily.sonyDualShock4"
    )
    #expect(
      PhysicalProtocolID.vendorPS3ThirdParty.displayNameKey
        == "term.protocolFamily.vendorPs3ThirdParty"
    )

    let english = Localization(preferredLanguages: ["en-US"])
    let names = PhysicalProtocolID.allCases.map { english.string($0.displayNameKey) }
    #expect(Set(names).count == names.count)
    #expect(
      english.string(PhysicalProtocolID.sonyDualShock4.displayNameKey) == "Sony DualShock 4"
    )
  }

  @Test
  func everyVariantThatABindingNamesHasOneDisplayNameKey() {
    let sourceKeys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    let named = PhysicalProtocolID.allCases.filter(\.namesVariant)
    #expect(
      Set(named) == [.xboxXUSB, .valveSteamController, .valveSteamTriton, .vendorGameSir]
    )
    let variantKeys = Set(named.flatMap(\.variants).map(\.displayNameKey))
    #expect(
      variantKeys == [
        "term.protocolVariant.wired", "term.protocolVariant.receiver",
        "term.protocolVariant.dongle", "term.protocolVariant.usb",
        "term.protocolVariant.enhancedHid", "term.protocolVariant.bluetoothLe",
      ]
    )
    #expect(variantKeys.isSubset(of: sourceKeys), "\(variantKeys.subtracting(sourceKeys).sorted())")
    let catalogVariantKeys = sourceKeys.filter { $0.hasPrefix("term.protocolVariant.") }
    #expect(
      catalogVariantKeys == variantKeys,
      "\(catalogVariantKeys.subtracting(variantKeys).sorted())"
    )
    for locale in Localization.availableLocalizations() {
      let values = LocalizationCatalogAudit.values(for: locale)
      let names = variantKeys.sorted().map { values[$0] }
      #expect(Set(names).count == names.count, "\(locale) \(names)")
    }
  }

  @Test
  func aReceiverBindingReadsAsTheFamilyThenTheVariantInEnglish() {
    let english = Localization(preferredLanguages: ["en-US"])
    #expect(
      ProtocolBindingID(.xboxXUSB, variant: .receiver).displayName(in: english)
        == "Xbox 360 (XUSB), Receiver"
    )
  }

  @Test
  func aBindingNamesItsVariantOnlyWhenTheFamilyStoresIt() {
    let english = Localization(preferredLanguages: ["en-US"])
    #expect(english.string("term.protocolBinding.familyWithVariant", "A", "B") == "A, B")
    let receiver = ProtocolBindingID(.xboxXUSB, variant: .receiver)
    #expect(
      receiver.displayName
        == Localization().string(
          "term.protocolBinding.familyWithVariant",
          PhysicalProtocolID.xboxXUSB.displayName,
          Localization().string("term.protocolVariant.receiver")
        )
    )
    #expect(receiver.displayName != ProtocolBindingID(.xboxXUSB, variant: .wired).displayName)
    #expect(
      ProtocolBindingID(.vendorGameSir, variant: .usb).displayName
        != ProtocolBindingID(.vendorGameSir, variant: .enhancedHID).displayName
    )
    for binding in [
      ProtocolBindingID(.xboxGIP, variant: .usb), ProtocolBindingID(.xboxXID, variant: .gamepad),
      ProtocolBindingID(.sonyDualSense, variant: .bluetoothClassic),
      ProtocolBindingID(.hidDescriptor),
    ] {
      #expect(binding.displayName == binding.protocolID.displayName, "\(binding)")
    }
  }

  @Test
  func brandAndTechnicalNamesEqualTheSourceInEveryLocale() {
    let source = LocalizationCatalogAudit.values(for: Localization.sourceLocalization)
    let listed = LocalizationCatalogAudit.sameInEveryLocaleKeys
    #expect(listed.isSubset(of: Set(source.keys)), "\(listed.subtracting(source.keys).sorted())")
    for locale in Localization.availableLocalizations() {
      let values = LocalizationCatalogAudit.values(for: locale)
      for key in listed.sorted() {
        #expect(values[key] == source[key], "\(locale) \(key)")
      }
    }
  }
}
