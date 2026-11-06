#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The label of a remapping destination: for a keyboard key, the symbols of its modifiers and
  /// key, and text for every other destination.
  ///
  /// A key shows an SF Symbol when this macOS has it and localized text otherwise.
  struct KeyboardDestinationLabel: View {
    /// The destination to label.
    let destination: RemappingDestination

    /// The label of the destination: the key row for a keyboard key, else the destination's text.
    var body: some View {
      switch destination {
      case .keyboard(let key, let modifiers): keyboardRow(key: key, modifiers: modifiers)
      case .mouseButton, .mouseMovement, .scroll, .gamepadButton, .gamepadDpad, .gamepadAxis,
        .physical:
        Text(RuntimePresentation.destinationLabel(destination))
      }
    }

    /// Returns the modifier and key symbols, which VoiceOver reads as the label of the destination.
    private func keyboardRow(
      key: RemappingKeyboardKey,
      modifiers: Set<RemappingKeyModifier>
    ) -> some View {
      let ordered = modifiers.sorted { $0.rawValue < $1.rawValue }
      return HStack(spacing: 4) {
        ForEach(ordered, id: \.self) { modifier in
          OJDSystemSymbol(
            name: RuntimePresentation.modifierSystemSymbolName(modifier),
            fallback: RuntimePresentation.modifierLabel(modifier)
          )
          Text("+")
        }
        keyGlyph(key)
      }.accessibilityElement(children: .ignore).ojdAccessibilityLabel(
        RuntimePresentation.destinationLabel(destination)
      )
    }

    /// Returns the SF Symbol of the key, or its text when the key has no symbol.
    @ViewBuilder
    private func keyGlyph(_ key: RemappingKeyboardKey) -> some View {
      if let name = RuntimePresentation.keyboardSystemSymbolName(key) {
        OJDSystemSymbol(
          name: name,
          fallback: RuntimePresentation.keyboardKeyLabel(key),
          fallbackSymbolName: RuntimePresentation.keyboardSystemSymbolFallbackName(key)
        )
      } else {
        Text(RuntimePresentation.keyboardKeyLabel(key))
      }
    }
  }

#endif
