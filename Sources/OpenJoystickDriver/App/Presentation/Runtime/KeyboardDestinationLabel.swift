#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  // Keyboard remapping row: SF Symbol when this macOS has it, localized text otherwise.
  struct KeyboardDestinationLabel: View {
    let destination: RemappingDestination

    var body: some View {
      switch destination {
      case .keyboard(let key, let modifiers):
        keyboardRow(key: key, modifiers: modifiers)
      case .mouseButton, .mouseMovement, .scroll:
        Text(RuntimePresentation.destinationLabel(destination))
      }
    }

    private func keyboardRow(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
      -> some View
    {
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

    @ViewBuilder private func keyGlyph(_ key: RemappingKeyboardKey) -> some View {
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
