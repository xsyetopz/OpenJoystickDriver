import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct LocalizationTests {
  @Test func packagesTheCompleteLocaleInventory() {
    let localizations = Localization.availableLocalizations()
    #expect(localizations.count == 83)
    let normalized = Set(localizations.map { $0.lowercased() })
    #expect(normalized.contains("en-us"))
    #expect(normalized.contains("ar-sa"))
    #expect(normalized.contains("he-il"))
    #expect(normalized.contains("fa-ir"))
    #expect(normalized.contains("c"))
  }

  @Test func everyLocaleHasTheSameCurrentCatalogShape() {
    let sourceKeys = Localization.catalogKeys(for: Localization.sourceLocalization)
    let sourcePlaceholders = Localization.catalogPlaceholderSignatures(
      for: Localization.sourceLocalization
    )
    #expect(!sourceKeys.isEmpty)
    #expect(sourceKeys.count == sourcePlaceholders.count)

    for locale in Localization.availableLocalizations() {
      #expect(Localization.catalogKeys(for: locale) == sourceKeys)
      #expect(Localization.catalogPlaceholderSignatures(for: locale) == sourcePlaceholders)
    }
  }

  @Test func pluralResourcesExposeNativeLocaleCategories() {
    let expectedCategories: Set<String> = ["zero", "one", "two", "few", "many", "other"]
    let sourceCategories = Localization.catalogPluralCategories()
    #expect(sourceCategories["status.controllerConnected"] == expectedCategories)
    #expect(sourceCategories["profiles.assignments"] == expectedCategories)
    #expect(sourceCategories["debug.devices"] == expectedCategories)
    #expect(
      Localization.catalogPluralCategories(for: "ar-SA")["status.controllerConnected"]
        == expectedCategories
    )
    #expect(
      Localization.catalogPluralCategories(for: "ru-RU")["profiles.assignments"]
        == expectedCategories
    )

    let resolver = Localization(preferredLanguages: ["en-US"])
    #expect(
      resolver.plural(
        "status.controllerConnected",
        count: 1,
        defaultValue: "%d controllers connected"
      ) == "1 controller connected"
    )
    #expect(
      resolver.plural(
        "status.controllerConnected",
        count: 2,
        defaultValue: "%d controllers connected"
      ) == "2 controllers connected"
    )
    #expect(
      resolver.plural(
        "debug.outputDevices",
        count: 0,
        defaultValue: "%d controller output devices detected"
      ) == "No controller output devices detected"
    )
  }

  @Test func preferredLanguageSelectionUsesTheLocaleCatalog() {
    let resolver = Localization(preferredLanguages: ["et-EE", "en-US"])
    #expect(resolver.resolvedLanguage?.lowercased() == "et-ee")
    #expect(resolver.string("common.refresh", defaultValue: "Refresh") == "Värskenda")

    let missing = resolver.string("test.missing.key", defaultValue: "Source fallback")
    #expect(missing == "Source fallback")
  }

  @Test func incompleteLocaleFallsBackToSourceEnglishResource() throws {
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
    #expect(resolver.string("frOnly", defaultValue: "Caller fallback") == "French value")
    #expect(resolver.string("shared", defaultValue: "Caller fallback") == "English source")
    #expect(resolver.string("missing", defaultValue: "Caller fallback") == "Caller fallback")
  }

  @Test func resolverCachesLocaleDiscoveryAtInitialization() throws {
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

  @Test func formattedValuesPreserveCatalogPlaceholders() {
    let resolver = Localization(preferredLanguages: ["en-US"])
    let value = resolver.plural(
      "status.controllerConnected",
      count: 3,
      defaultValue: "%d controllers connected"
    )
    #expect(value == "3 controllers connected")

    let about = resolver.formatted(
      "about.version",
      defaultValue: "Version %@\nController input for macOS",
      arguments: ["1.2.3" as CVarArg]
    )
    #expect(about == "Version 1.2.3\nController input for macOS")
  }
}
