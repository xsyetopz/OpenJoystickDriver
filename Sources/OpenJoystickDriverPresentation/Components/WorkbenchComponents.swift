#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  // SF Symbol via NSImage(systemSymbolName:), else fallback text. Pass a nil fallback for a
  // decorative glyph whose meaning is already printed beside it: fallback text in a glyph-sized
  // frame wraps into a column. The symbol's accessibility label is the fallback text; a nil
  // fallback hides the symbol from VoiceOver.
  /// An SF Symbol, or text when the symbol does not exist.
  ///
  /// The symbol falls back to `fallbackSymbolName` first, then to the fallback text.
  struct OJDSystemSymbol: View {
    /// The name of the SF Symbol.
    let name: String
    /// The text to show when no symbol exists; nil hides the glyph from VoiceOver.
    let fallback: String?
    /// The name of a second SF Symbol to try when `name` does not exist.
    let fallbackSymbolName: String?

    /// Creates the symbol with a preferred name, a text fallback and an optional fallback symbol.
    init(name: String, fallback: String?, fallbackSymbolName: String? = nil) {
      self.name = name
      self.fallback = fallback
      self.fallbackSymbolName = fallbackSymbolName
    }

    /// The symbol image, or the fallback when the symbol is not available.
    var body: some View {
      let preferredImage = NSImage(systemSymbolName: name, accessibilityDescription: nil)
      let fallbackImage = fallbackSymbolName.flatMap {
        NSImage(systemSymbolName: $0, accessibilityDescription: nil)
      }
      switch SystemSymbolPolicy.resolution(
        preferred: name,
        fallback: fallbackSymbolName,
        preferredIsAvailable: preferredImage != nil,
        fallbackIsAvailable: fallbackImage != nil
      ) {
      case .symbol(let resolvedName):
        if resolvedName == name, let preferredImage {
          Image(nsImage: preferredImage).ojdSymbolAccessibility(fallback)
        } else if let fallbackImage {
          Image(nsImage: fallbackImage).ojdSymbolAccessibility(fallback)
        }
      case .text: if let fallback { Text(fallback).font(.body) }
      }
    }
  }

  /// A fixed 28-point square that holds the glyph in front of a list row's title.
  struct OJDListGlyphSlot<Content: View>: View {
    /// The glyph.
    let content: Content

    /// Creates the slot around `content`.
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    /// The content in a fixed square, hidden from VoiceOver.
    var body: some View {
      content.font(.title3.weight(.medium)).frame(
        width: 28,
        height: 28,
        alignment: .center
      ).accessibilityHidden(true)
    }
  }

  /// A borderless button that shows a symbol, with a label for its tooltip and VoiceOver.
  struct OJDCompactSymbolButton: View {
    /// The name of the SF Symbol.
    let symbolName: String
    /// The name of a second SF Symbol to try when `symbolName` does not exist.
    let fallbackSymbolName: String?
    /// The tooltip and VoiceOver label.
    let label: String
    /// Runs when the user presses the button.
    let action: () -> Void

    /// Creates the button.
    init(
      symbolName: String,
      fallbackSymbolName: String? = nil,
      label: String,
      action: @escaping () -> Void
    ) {
      self.symbolName = symbolName
      self.fallbackSymbolName = fallbackSymbolName
      self.label = label
      self.action = action
    }

    /// The borderless button with the symbol, labeled for VoiceOver and help.
    var body: some View {
      Button(action: action) {
        OJDSystemSymbol(name: symbolName, fallback: label, fallbackSymbolName: fallbackSymbolName)
          .frame(minWidth: 28, minHeight: 28).contentShape(Rectangle())
      }.buttonStyle(BorderlessButtonStyle()).ojdAccessibilityLabel(label).help(label)
    }
  }

  extension View {
    /// Sets the VoiceOver label of the view.
    func ojdAccessibilityLabel(_ label: String) -> some View { accessibilityLabel(Text(label)) }

    /// Sets the VoiceOver label of a symbol, or hides the symbol from VoiceOver when `label` is
    /// nil.
    @ViewBuilder
    func ojdSymbolAccessibility(_ label: String?) -> some View {
      if let label { accessibilityLabel(Text(label)) } else { accessibilityHidden(true) }
    }

    /// Sets the VoiceOver value of the view.
    func ojdAccessibilityValue(_ value: String) -> some View { accessibilityValue(Text(value)) }

    /// Sets the VoiceOver value to Selected or Not Selected and adds the selected trait when it is
    /// selected.
    @ViewBuilder
    func ojdAccessibilitySelection(_ selected: Bool) -> some View {
      let value = OJDLocalized.string(
        selected ? "status.selected" : "status.notSelected"
      )
      accessibilityValue(Text(value)).accessibilityAddTraits(selected ? .isSelected : [])
    }
  }

#endif
