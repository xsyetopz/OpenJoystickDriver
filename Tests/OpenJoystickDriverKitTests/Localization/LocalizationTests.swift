import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LocalizationTests {
  @Test
  func packagesTheCompleteLocaleInventory() {
    let localizations = Localization.availableLocalizations()
    #expect(localizations.count == 20)
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
  func packagedCatalogIncludesCLIAndInputTestProductKeys() {
    let keys = LocalizationCatalogAudit.keys(for: Localization.sourceLocalization)
    for required in [
      "cli.root.abstract", "cli.error.service_unavailable", "cli.service.start.abstract",
      "cli.status.label.controllers", "inputTest.controls", "inputTest.additionalButtons",
      "virtualProfile.title", "setup.openSystemSettings", "controllers.battery",
      "controllers.chargingState", "controllers.cableState", "controllers.discharging",
      "controllers.charging", "controllers.batteryFull", "controllers.batteryAccessibilityDetails",
      "profiles.actions", "profiles.editorSection", "profiles.combinations",
    ] { #expect(keys.contains(required)) }
    #expect(!keys.contains { $0.hasPrefix("compatibility.") || $0.hasPrefix("identity.") })
    #expect(!keys.contains { $0.hasPrefix("cli.compat.") || $0 == "cli.catalog.compat.summary" })
    #expect(!keys.contains { $0.hasPrefix("cli.settings.reset.") })
    #expect(keys.filter { $0.hasPrefix("inputTest.") }.count >= 20)
  }

  @Test
  func pluralResourcesExposeNativeLocaleCategories() {
    let expectedCategories: Set<String> = ["zero", "one", "two", "few", "many", "other"]
    let sourceCategories = LocalizationCatalogAudit.pluralCategories(
      for: Localization.sourceLocalization
    )
    #expect(sourceCategories["status.controllerConnected"] == expectedCategories)
    #expect(sourceCategories["profiles.assignments"] == expectedCategories)
    #expect(sourceCategories["debug.devices"] == expectedCategories)
    #expect(
      LocalizationCatalogAudit.pluralCategories(for: "ar-SA")["status.controllerConnected"]
        == expectedCategories
    )
    #expect(
      LocalizationCatalogAudit.pluralCategories(for: "ja-JP")["profiles.assignments"]
        == expectedCategories
    )
    #expect(
      LocalizationCatalogAudit.pluralCategories(for: "ru-RU")["profiles.assignments"]
        == expectedCategories
    )

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
        "debug.outputDevices",
        count: 0
      ) == "No controller output devices detected"
    )
  }

  @Test
  func preferredLanguageSelectionUsesTheLocaleCatalog() {
    let resolver = Localization(preferredLanguages: ["fr-FR", "en-US"])
    #expect(resolver.resolvedLanguage?.lowercased() == "fr-fr")
    #expect(resolver.string("common.refresh") == "Actualiser")

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

    let about = resolver.formatted(
      "about.version",
      arguments: ["1.2.3" as CVarArg]
    )
    #expect(about == "Version 1.2.3\nController input for macOS")
  }
}
