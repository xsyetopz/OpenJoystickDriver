import AppKit
import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

/// AppKit and SwiftUI colors are resolved and released on the main thread only, so the suite
/// runs there.
@MainActor
struct LibraryRecordTextTests {
  /// A record text as the catalog holds it: the `plistData()` of a record.
  private static let document: String = {
    let record: [String: Any] = [
      "apiVersion": "openjoystickdriver/v1alpha3",
      "kind": "Controller",
      "vendorID": 13629,
      "productID": 4296,
      "scale": 0.5,
      "enabled": true,
      "note": "a < b & c",
      "modes": [["id": "default", "vendorID": 99, "protocol": ["family": "XboxGIP"]]],
      "empty": [String](),
    ]
    guard let data = try? OrderedJSON(foundation: record).plistData(),
      let text = String(bytes: data, encoding: .utf8)
    else { fatalError("the record does not encode") }
    return text
  }()

  private func text() throws -> LibraryRecordText {
    try LibraryRecordText(document: Self.document)
  }

  private func line(_ text: LibraryRecordText, containing part: String) throws -> Int {
    try #require(text.lines.firstIndex { $0.contains(part) })
  }

  @Test
  func theTextTheCatalogHoldsIsAnXMLPropertyList() {
    #expect(Self.document.hasPrefix("<?xml"))
    #expect(!Self.document.hasPrefix("{"))
  }

  @Test
  func onlyTheTopLevelVendorAndProductLinesGetAReading() throws {
    let text = try text()
    let vendor = try line(text, containing: "<integer>13629</integer>")
    let product = try line(text, containing: "<integer>4296</integer>")

    #expect(
      text.identifierReadings == [
        vendor: .init(key: "vendorID", hexadecimal: "0x353D"),
        product: .init(key: "productID", hexadecimal: "0x10C8"),
      ]
    )
    #expect(text.lines[vendor - 1].contains("<key>vendorID</key>"))
  }

  @Test
  func aNestedVendorIDGetsNoReading() throws {
    let text = try text()
    let nested = try line(text, containing: "<integer>99</integer>")

    #expect(text.identifierReadings[nested] == nil)
  }

  @Test
  func readingsUseUppercaseHexWithFourDigits() throws {
    let text = try LibraryRecordText(
      document:
        "<plist><dict>\n<key>vendorID</key>\n<integer>1</integer>\n<key>productID</key>\n"
        + "<integer>65535</integer>\n</dict></plist>\n"
    )

    #expect(text.identifierReadings.mapValues(\.hexadecimal) == [2: "0x0001", 4: "0xFFFF"])
  }

  @Test
  func aVendorIDKeyWithAStringValueGetsNoReading() throws {
    let text = try LibraryRecordText(
      document: "<plist><dict>\n<key>vendorID</key>\n<string>13629</string>\n</dict></plist>\n"
    )

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func aNumberOutsideTheIdentifierRangeGetsNoReading() throws {
    let text = try LibraryRecordText(
      document: "<plist><dict>\n<key>vendorID</key>\n<integer>70000</integer>\n</dict></plist>\n"
    )

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func copyTextIsTheDocumentAndAPropertyList() throws {
    let text = try text()

    #expect(text.copyText == Self.document)
    let object = try DocumentCoder.read(Data(text.copyText.utf8), file: "record.plist")
    #expect((object as? [String: Any])?["vendorID"] as? Int == 13629)
    #expect(!text.copyText.contains("0x"))
  }

  @Test
  func theShownLinesAreTheDocumentLinesWithNoReading() throws {
    let text = try text()

    #expect(text.lines.joined(separator: "\n") + "\n" == Self.document)
    #expect(text.lines.allSatisfy { !$0.contains("0x") })
    #expect(text.tokens.map(\.text).joined() == Self.document)
  }

  @Test
  func theTokensColorKeysValuesAndTags() throws {
    let tokens = try text().tokens

    func kinds(of text: String) -> Set<RecordSyntaxKind> {
      Set(tokens.filter { $0.text == text }.map(\.kind))
    }
    #expect(kinds(of: "vendorID") == [.key])
    #expect(kinds(of: "Controller") == [.string])
    #expect(kinds(of: "13629") == [.number])
    #expect(kinds(of: "0.5") == [.number])
    #expect(kinds(of: "<true/>") == [.literal])
    #expect(kinds(of: "a &lt; b &amp; c") == [.string])
    #expect(kinds(of: "<dict>") == [.punctuation])
    #expect(kinds(of: "<array/>") == [.punctuation])
  }

  @Test
  func theHighlightedTextHoldsNoReading() throws {
    let text = try text()
    let shown = String(text.highlighted.characters)

    #expect(shown + "\n" == Self.document)
    #expect(!shown.contains("0x"))
  }

  /// The WCAG contrast ratio of `color` against `textBackgroundColor` in `appearance`.
  ///
  /// AppKit gives the light or dark appearance for a high-contrast name, so the background is the
  /// one of the light or dark appearance.
  private static func contrast(_ color: NSColor, in appearance: NSAppearance.Name) throws -> Double
  {
    let shown = try #require(NSAppearance(named: appearance))
    var ratio = 0.0
    var failure: String?
    shown.performAsCurrentDrawingAppearance {
      guard let fore = color.usingColorSpace(.sRGB),
        let back = NSColor.textBackgroundColor.usingColorSpace(.sRGB)
      else {
        failure = "\(color) has no sRGB form in \(appearance.rawValue)"
        return
      }
      func luminance(_ color: NSColor) -> Double {
        func linear(_ channel: CGFloat) -> Double {
          let value = Double(channel)
          return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent)
          + 0.0722 * linear(color.blueComponent)
      }
      let (high, low) = (
        max(luminance(fore), luminance(back)), min(luminance(fore), luminance(back))
      )
      ratio = (high + 0.05) / (low + 0.05)
    }
    if let failure { Issue.record(Comment(rawValue: failure)) }
    return ratio
  }

  private static let coloredKinds: [RecordSyntaxKind] = [
    .key, .string, .number, .literal, .punctuation,
  ]

  /// The contrast of each shade of `kind`, by appearance index.
  private static func contrasts(_ kind: RecordSyntaxKind) throws -> [Double] {
    let shades = try #require(kind.shades)
    #expect(shades.count == RecordSyntaxKind.appearances.count)
    return try zip(shades, RecordSyntaxKind.appearances).map { shade, appearance in
      try contrast(RecordSyntaxKind.color(shade), in: appearance)
    }
  }

  @Test
  func everyShadeReadsAtLeast4_5To1AndSevenWithIncreasedContrast() throws {
    for kind in Self.coloredKinds {
      let ratios = try Self.contrasts(kind)
      for (ratio, appearance) in zip(ratios, RecordSyntaxKind.appearances) {
        let increased =
          appearance == .accessibilityHighContrastAqua
          || appearance == .accessibilityHighContrastDarkAqua
        #expect(ratio >= (increased ? 7 : 4.5), "\(kind) in \(appearance.rawValue): \(ratio)")
      }
    }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theColorTakesTheShadeOfTheAppearance(_ appearance: NSAppearance.Name) throws {
    let index = try #require(RecordSyntaxKind.appearances.firstIndex(of: appearance))
    for kind in Self.coloredKinds {
      let shade = try #require(kind.shades)[index]
      #expect(
        try Self.contrast(kind.color, in: appearance)
          == Self.contrast(RecordSyntaxKind.color(shade), in: appearance)
      )
    }
    #expect(RecordSyntaxKind.space.color == .labelColor)
  }

  @Test
  func anAppearanceMatchingNoneOfTheFourGetsTheLightShade() {
    #expect(RecordSyntaxKind.shadeIndex(matching: nil) == RecordSyntaxKind.lightShadeIndex)
    #expect(RecordSyntaxKind.appearances[RecordSyntaxKind.lightShadeIndex] == .aqua)
    for (index, name) in RecordSyntaxKind.appearances.enumerated() {
      #expect(RecordSyntaxKind.shadeIndex(matching: name) == index)
    }
    #expect(RecordSyntaxKind.shadeIndex(matching: .darkAqua) == 1)
  }

  @Test
  func everyKindHasAColorAndPunctuationRecedes() throws {
    for index in RecordSyntaxKind.appearances.indices {
      let shades = Self.coloredKinds.compactMap { $0.shades?[index] }
      #expect(Set(shades).count == Self.coloredKinds.count)
    }
    let punctuation = try Self.contrasts(.punctuation)
    for kind in Self.coloredKinds where kind != .punctuation {
      for (ratio, receding) in zip(try Self.contrasts(kind), punctuation) {
        #expect(ratio > receding, "\(kind)")
      }
    }
  }

  @Test
  func theStoreSaysWhenTheTokenizerCannotReadTheDocument() {
    var logged: [String] = []
    #expect(
      LibraryRecordDocument(document: "<dict>") { logged.append($0) }
        == .unreadable(RecordSyntaxError(offset: 6, reason: "<dict> is not closed"))
    )
    #expect(
      logged == [
        "[Library] The record text cannot be shown: record text, scalar 6: <dict> is not closed\n"
      ]
    )
    logged = []
    let read = LibraryRecordDocument(document: Self.document) { logged.append($0) }
    guard case .text(let text) = read else {
      Issue.record("the document is not read")
      return
    }
    #expect(text.copyText == Self.document)
    #expect(logged.isEmpty)
  }

  @Test
  func textTheTokenizerCannotReadThrows() {
    #expect(throws: RecordSyntaxError.self) { try LibraryRecordText(document: "{ vendorID: 1 }") }
    #expect(throws: RecordSyntaxError.self) { try LibraryRecordText(document: "<a></b>") }
  }
}
