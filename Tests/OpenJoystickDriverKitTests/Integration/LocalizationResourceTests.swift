import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite("Localization resources")
struct LocalizationResourceTests {

  @Test("source locale resources match normalized macOS locale list without duplicates")
  func sourceLocaleResourcesMatchNormalizedMacOSLocaleList() throws {
    let expectedLocales: Set<String> = [
    "C",
    "af-ZA",
    "am-ET",
    "ar-AE",
    "ar-EG",
    "ar-JO",
    "ar-MA",
    "ar-QA",
    "ar-SA",
    "be-BY",
    "bg-BG",
    "ca-AD",
    "ca-ES",
    "ca-FR",
    "ca-IT",
    "cs-CZ",
    "da-DK",
    "de-AT",
    "de-CH",
    "de-DE",
    "el-GR",
    "en-AU",
    "en-CA",
    "en-GB",
    "en-HK",
    "en-IE",
    "en-IN",
    "en-NZ",
    "en-PH",
    "en-SG",
    "en-US",
    "en-ZA",
    "es-AR",
    "es-CR",
    "es-ES",
    "es-MX",
    "et-EE",
    "eu-ES",
    "fa-AF",
    "fa-IR",
    "fi-FI",
    "fr-BE",
    "fr-CA",
    "fr-CH",
    "fr-FR",
    "ga-IE",
    "he-IL",
    "hi-IN",
    "hr-HR",
    "hu-HU",
    "hy-AM",
    "is-IS",
    "it-CH",
    "it-IT",
    "ja-JP",
    "kk-KZ",
    "ko-KR",
    "lt-LT",
    "lv-LV",
    "mn-MN",
    "nb-NO",
    "nl-BE",
    "nl-NL",
    "nn-NO",
    "no-NO",
    "pl-PL",
    "pt-BR",
    "pt-PT",
    "ro-RO",
    "ru-RU",
    "se-FI",
    "se-NO",
    "sk-SK",
    "sl-SI",
    "sr-RS",
    "sr-YU",
    "sv-FI",
    "sv-SE",
    "tr-TR",
    "uk-UA",
    "zh-CN",
    "zh-HK",
    "zh-TW",
    ]
    let resourceRoot = try RepositoryRoot.from()
      .appendingPathComponent("Sources/OpenJoystickDriverKit/Resources")
    let sourceLocales = try FileManager.default.contentsOfDirectory(
      at: resourceRoot,
      includingPropertiesForKeys: nil
    )
      .filter { $0.pathExtension == "lproj" }
      .map { $0.deletingPathExtension().lastPathComponent }

    #expect(Set(sourceLocales) == expectedLocales)
    #expect(sourceLocales.count == Set(sourceLocales).count)
  }

  @Test("template and locale resources expose the same keys")
  func templateAndLocaleResourcesExposeSameKeys() throws {
    let templateURL = try #require(
      Bundle.module.url(
        forResource: "Localizable.template",
        withExtension: "strings"
      )
    )
    let templateKeys = try Self.keys(in: templateURL)
    let localeURLs = try #require(
      Bundle.module.urls(forResourcesWithExtension: "strings", subdirectory: nil)
    ).filter { $0.lastPathComponent == "Localizable.strings" }

    #expect(!templateKeys.isEmpty)
    #expect(!localeURLs.isEmpty)
    for url in localeURLs {
      #expect(try Self.keys(in: url) == templateKeys)
    }
  }

  @Test("only POSIX and English locale resources use the English template text")
  func onlyPosixAndEnglishLocaleResourcesUseEnglishTemplateText() throws {
    let expectedTemplateCopyLocales: Set<String> = [
      "C",
      "en-AU",
      "en-CA",
      "en-GB",
      "en-HK",
      "en-IE",
      "en-IN",
      "en-NZ",
      "en-PH",
      "en-SG",
      "en-US",
      "en-ZA",
    ]
    let resourceRoot = try RepositoryRoot.from()
      .appendingPathComponent("Sources/OpenJoystickDriverKit/Resources")
    let templateText = try String(
      contentsOf: resourceRoot
        .appendingPathComponent("Localization/Localizable.template.strings"),
      encoding: .utf8
    )
    let templateCopyLocales = try FileManager.default.contentsOfDirectory(
      at: resourceRoot,
      includingPropertiesForKeys: nil
    )
      .filter { $0.pathExtension == "lproj" }
      .filter {
        let localizableText = try String(
          contentsOf: $0.appendingPathComponent("Localizable.strings"),
          encoding: .utf8
        )
        return localizableText == templateText
      }
      .map { $0.deletingPathExtension().lastPathComponent }

    #expect(Set(templateCopyLocales) == expectedTemplateCopyLocales)
  }

  @Test("localized values contain no unexpected control characters")
  func localizedValuesContainNoUnexpectedControlCharacters() throws {
    let urls = try #require(
      Bundle.module.urls(forResourcesWithExtension: "strings", subdirectory: nil)
    )
    for url in urls {
      let data = try Data(contentsOf: url)
      let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      )
      let strings = try #require(plist as? [String: String])
      for (key, value) in strings {
        let unexpected = value.unicodeScalars.filter {
          $0.value < 0x20 && $0.value != 0x09 && $0.value != 0x0A
        }
        #expect(
          unexpected.isEmpty,
          "Unexpected control character in \(url.lastPathComponent):\(key)"
        )
      }
    }
  }

  @Test("literal application localization keys exist in the template")
  func literalApplicationLocalizationKeysExistInTemplate() throws {
    let root = try RepositoryRoot.from()
    let sourceRoot = root.appendingPathComponent("Sources/OpenJoystickDriver")
    let templateURL = root.appendingPathComponent(
      "Sources/OpenJoystickDriverKit/Resources/Localization/Localizable.template.strings"
    )
    let templateKeys = try Self.keys(in: templateURL)
    let expression = try NSRegularExpression(
      pattern: #"L10n\.string\("([^"]+)""#
    )
    let enumerator = try #require(
      FileManager.default.enumerator(
        at: sourceRoot,
        includingPropertiesForKeys: nil
      )
    )
    var referencedKeys = Set<String>()

    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let source = try String(contentsOf: url, encoding: .utf8)
      let range = NSRange(source.startIndex..., in: source)
      for match in expression.matches(in: source, range: range) {
        guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
        referencedKeys.insert(String(source[keyRange]))
      }
    }

    let missingKeys = referencedKeys.subtracting(templateKeys)
    #expect(missingKeys.isEmpty, "Missing localization keys: \(missingKeys.sorted())")
  }

  @Test("localized UI does not describe the removed helper identity")
  func localizedUIDoesNotDescribeRemovedHelperIdentity() throws {
    let urls = try #require(
      Bundle.module.urls(forResourcesWithExtension: "strings", subdirectory: nil)
    )
    for url in urls {
      let value = try String(contentsOf: url, encoding: .utf8).lowercased()
      #expect(!value.contains("daemon"), "Obsolete helper wording in \(url.path)")
    }
  }

  @Test("developer-only GUI localization families are absent")
  func developerOnlyGUILocalizationFamiliesAreAbsent() throws {
    let templateURL = try #require(
      Bundle.module.url(
        forResource: "Localizable.template",
        withExtension: "strings"
      )
    )
    let keys = try Self.keys(in: templateURL)
    for prefix in ["browserDiagnostic.", "runtimeHealth.", "appleCatalog."] {
      #expect(!keys.contains { $0.hasPrefix(prefix) })
    }
  }

  @Test("bundle localization follows the user's preferred macOS locale")
  func bundleLocalizationFollowsPreferredLocale() {
    let localization = Localization(preferredLanguages: ["en-US"])

    #expect(localization.string("app.quit") == "Quit")
  }

  private static func keys(in url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    )
    guard let strings = plist as? [String: String] else {
      Issue.record("Expected strings plist at \(url.path)")
      return []
    }
    return Set(strings.keys)
  }
}
