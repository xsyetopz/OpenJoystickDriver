import AppKit
import Foundation
import Testing

@testable import OpenJoystickDriverPresentation

/// AppKit and SwiftUI colors are resolved and released on the main thread only, so the suite
/// runs there.
@MainActor
struct LibraryRecordTextTests {
  private static let document = """
    {
      "apiVersion": "openjoystickdriver/v1alpha2",
      "kind": "Controller",
      "vendorID": 13629,
      "productID": 4296,
      "modes": [
        {
          "id": "default",
          "vendorID": 99,
          "protocol": {
            "family": "XboxGIP"
          }
        }
      ]
    }

    """

  private func text() throws -> LibraryRecordText {
    try LibraryRecordText(document: Self.document)
  }

  @Test
  func onlyTheTopLevelVendorAndProductLinesGetAReading() throws {
    let text = try text()

    #expect(
      text.identifierReadings == [
        3: .init(key: "vendorID", hexadecimal: "0x353D"),
        4: .init(key: "productID", hexadecimal: "0x10C8"),
      ]
    )
    #expect(text.lines[3] == "  \"vendorID\": 13629,")
    #expect(text.lines[4] == "  \"productID\": 4296,")
  }

  @Test
  func aNestedVendorIDGetsNoReading() throws {
    let text = try text()

    #expect(text.lines[8] == "      \"vendorID\": 99,")
    #expect(text.identifierReadings[8] == nil)
  }

  @Test
  func readingsUseUppercaseHexWithFourDigits() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": 1,\n  \"productID\": 65535\n}\n")

    #expect(text.identifierReadings.mapValues(\.hexadecimal) == [1: "0x0001", 2: "0xFFFF"])
  }

  @Test
  func aVendorIDKeyWithAStringValueGetsNoReading() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": \"13629\"\n}\n")

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func aNumberOutsideTheIdentifierRangeGetsNoReading() throws {
    let text = try LibraryRecordText(document: "{\n  \"vendorID\": 70000\n}\n")

    #expect(text.identifierReadings.isEmpty)
  }

  @Test
  func copyTextIsTheDocumentAndValidJSON() throws {
    let text = try text()

    #expect(text.copyText == Self.document)
    let object = try JSONSerialization.jsonObject(with: Data(text.copyText.utf8))
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

  private static let coloredKinds: [JSONSyntaxKind] = [
    .key, .string, .number, .literal, .punctuation,
  ]

  /// The contrast of each shade of `kind`, by appearance index.
  private static func contrasts(_ kind: JSONSyntaxKind) throws -> [Double] {
    let shades = try #require(kind.shades)
    #expect(shades.count == JSONSyntaxKind.appearances.count)
    return try zip(shades, JSONSyntaxKind.appearances).map { shade, appearance in
      try contrast(JSONSyntaxKind.color(shade), in: appearance)
    }
  }

  @Test
  func everyShadeReadsAtLeast4_5To1AndSevenWithIncreasedContrast() throws {
    for kind in Self.coloredKinds {
      let ratios = try Self.contrasts(kind)
      for (ratio, appearance) in zip(ratios, JSONSyntaxKind.appearances) {
        let increased =
          appearance == .accessibilityHighContrastAqua
          || appearance == .accessibilityHighContrastDarkAqua
        #expect(ratio >= (increased ? 7 : 4.5), "\(kind) in \(appearance.rawValue): \(ratio)")
      }
    }
  }

  @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
  func theColorTakesTheShadeOfTheAppearance(_ appearance: NSAppearance.Name) throws {
    let index = try #require(JSONSyntaxKind.appearances.firstIndex(of: appearance))
    for kind in Self.coloredKinds {
      let shade = try #require(kind.shades)[index]
      #expect(
        try Self.contrast(kind.color, in: appearance)
          == Self.contrast(JSONSyntaxKind.color(shade), in: appearance)
      )
    }
    #expect(JSONSyntaxKind.space.color == .labelColor)
  }

  @Test
  func anAppearanceMatchingNoneOfTheFourGetsTheLightShade() {
    #expect(JSONSyntaxKind.shadeIndex(matching: nil) == JSONSyntaxKind.lightShadeIndex)
    #expect(JSONSyntaxKind.appearances[JSONSyntaxKind.lightShadeIndex] == .aqua)
    for (index, name) in JSONSyntaxKind.appearances.enumerated() {
      #expect(JSONSyntaxKind.shadeIndex(matching: name) == index)
    }
    #expect(JSONSyntaxKind.shadeIndex(matching: .darkAqua) == 1)
  }

  @Test
  func everyKindHasAColorAndPunctuationRecedes() throws {
    for index in JSONSyntaxKind.appearances.indices {
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
      LibraryRecordDocument(document: "[1 2]") { logged.append($0) }
        == .unreadable(
          JSONSyntaxError(offset: 3, reason: "unexpected \"2\" where JSON expects , or ]")
        )
    )
    #expect(
      logged == [
        "[Library] The record text cannot be shown: JSON text, scalar 3: unexpected \"2\" "
          + "where JSON expects , or ]\n"
      ]
    )
    guard case .text(let text) = LibraryRecordDocument(document: Self.document) else {
      Issue.record("the document is not read")
      return
    }
    #expect(text.copyText == Self.document)
  }

  @Test
  func textTheTokenizerCannotReadThrows() {
    #expect(throws: JSONSyntaxError.self) { try LibraryRecordText(document: "{ vendorID: 1 }") }
  }
}
