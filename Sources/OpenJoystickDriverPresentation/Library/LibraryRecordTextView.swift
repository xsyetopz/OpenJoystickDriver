#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import SwiftUI

  extension JSONSyntaxKind {
    /// The appearances a record color has a shade for, in the order of ``shades``.
    static let appearances: [NSAppearance.Name] = [
      .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    /// One sRGB shade, `0xRRGGBB`, per appearance in ``appearances``; nil for space, which shows
    /// nothing and keeps the label color.
    ///
    /// Every shade reaches at least 4.5:1 against `textBackgroundColor` (at least 7:1 with
    /// increased contrast), which the system blue, green and orange do not on white. Punctuation
    /// has the lowest contrast of the kinds, so it recedes behind keys and values.
    var shades: [UInt32]? {
      switch self {
      case .key: [0x0550AE, 0x79C0FF, 0x023B95, 0xB5DCFF]
      case .string: [0x116329, 0x7EE787, 0x024C1A, 0xA8F0B0]
      case .number: [0x953800, 0xFFA657, 0x702C00, 0xFFC68A]
      case .literal: [0x6639BA, 0xD2A8FF, 0x512A97, 0xE6CCFF]
      case .punctuation: [0x626A73, 0x9DA5AE, 0x474F58, 0xC2C8CF]
      case .space: nil
      }
    }

    /// Returns the index in ``appearances`` of the shade for the appearance that
    /// `NSAppearance.bestMatch(from:)` found, or the light shade when it found none.
    static func shadeIndex(matching name: NSAppearance.Name?) -> Int {
      name.flatMap(appearances.firstIndex(of:)) ?? lightShadeIndex
    }

    /// The shade of an appearance that matches none of ``appearances``.
    static let lightShadeIndex = 0

    /// A color that follows light and dark appearance and the increased contrast setting, with
    /// the shade of the best match among ``appearances``; an appearance that matches none of
    /// them gets the light shade (``lightShadeIndex``).
    var color: NSColor {
      guard let shades else { return .labelColor }
      return NSColor(name: "OpenJoystickDriver.record.\(self)") { appearance in
        Self.color(shades[Self.shadeIndex(matching: appearance.bestMatch(from: Self.appearances))])
      }
    }

    /// Returns the color for `value`, a shade `0xRRGGBB` in sRGB.
    static func color(_ value: UInt32) -> NSColor {
      NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
      )
    }
  }

  extension LibraryRecordText {
    /// The record JSON, colored by token, without the line break that ends the document.
    var highlighted: AttributedString {
      var shown = tokens
      if let last = shown.last, last.kind == .space, last.text.hasSuffix("\n") {
        shown.removeLast()
        let kept = String(last.text.dropLast())
        if !kept.isEmpty {
          shown.append(JSONSyntaxToken(kind: .space, text: kept, depth: last.depth))
        }
      }
      var result = AttributedString()
      for token in shown {
        var run = AttributedString(token.text)
        run.foregroundColor = Color(token.kind.color)
        result.append(run)
      }
      return result
    }
  }

  /// The record JSON in the Library detail: the code is one selectable block, and each
  /// identifier reading sits after its line as a separate element that selection and copying
  /// leave out.
  struct LibraryRecordTextView: View {
    /// The record text to show.
    let text: LibraryRecordText

    /// The monospaced font of the code and the readings.
    private static let font = Font.system(.body, design: .monospaced)

    /// The space between the end of a line and its reading.
    private static let gap = "   "

    /// The highlighted, selectable record text with its readings, and a menu that copies it.
    var body: some View {
      ScrollView(.horizontal) {
        Text(text.highlighted).font(Self.font).textSelection(.enabled)
          .fixedSize(horizontal: true, vertical: true)
          .overlay(readings, alignment: .topLeading)
      }.contextMenu {
        Button(OJDLocalized.string("action.copyAll")) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text.copyText, forType: .string)
        }
      }
    }

    /// One row per line of the block.
    ///
    /// Each row lays out a hidden copy of its line in the same font, so the row is as tall as the
    /// line and a reading starts where its line ends.
    private var readings: some View {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(text.lines.enumerated()), id: \.offset) { index, line in
          HStack(spacing: 0) {
            Text(line.isEmpty ? " " : line + Self.gap).font(Self.font).hidden()
              .accessibilityHidden(true)
            if let reading = text.identifierReadings[index] {
              Text(reading.hexadecimal).font(Self.font)
                .foregroundColor(Color(JSONSyntaxKind.punctuation.color))
                .ojdAccessibilityLabel(
                  OJDLocalized.formatted(
                    "a11y.library.recordHexadecimal",
                    reading.key,
                    reading.hexadecimal
                  )
                )
            }
          }.fixedSize()
        }
      }.allowsHitTesting(false)
    }
  }

#endif
