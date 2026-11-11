import Foundation
import OpenJoystickDriverKit

/// Whether the Controllers detail shows the selected controller's serial number.
///
/// It starts hidden, is not stored, and a detail view for another controller starts hidden again.
struct SerialNumberVisibility: Equatable {
  /// Whether the serial number shows.
  private(set) var isRevealed = false

  /// Shows the serial number when it is hidden, and hides it when it shows.
  mutating func toggle() { isRevealed.toggle() }

  /// Returns how the row presents the serial number.
  ///
  /// - Parameter serial: The serial number as reported.
  /// - Returns: How the row presents the serial number.
  func presentation(of serial: OJDValue) -> Presentation {
    Presentation(value: serial, isRevealed: isRevealed)
  }

  /// How the row presents the serial number.
  struct Presentation: Equatable {
    /// The serial number as reported.
    let value: OJDValue
    /// Whether the serial number shows.
    let isRevealed: Bool

    /// A missing serial number has nothing to hide, so it shows "None" and no eye button.
    var canToggle: Bool { value != .none }

    /// Whether a placeholder replaces the serial number.
    var isObscured: Bool { canToggle && !isRevealed }

    /// The text of the row.
    ///
    /// An obscured serial number is replaced by a placeholder of the same shape, so the real value
    /// is never in the view tree.
    var displayText: String {
      isObscured ? String(repeating: "\u{2022}", count: 12) : value.displayText
    }

    /// What VoiceOver and sentence templates read.
    var spokenText: String {
      isObscured ? OJDLocalized.string("ui.controllers.serial.hidden") : value.spokenText
    }

    /// The name of the eye symbol that the button shows.
    var toggleSymbolName: String { isRevealed ? "eye.slash" : "eye" }

    /// The localization key of the eye button's label.
    var toggleLabelKey: String {
      isRevealed ? "ui.controllers.serial.hide" : "ui.controllers.serial.show"
    }
  }
}

#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The Serial number row of the Controllers detail: blurred until the eye button reveals it.
  struct SerialNumberRow: View {
    /// The localized name of the row.
    let label: String
    /// The serial number as reported.
    let serial: OJDValue
    /// Whether the serial number shows.
    @Binding
    var visibility: SerialNumberVisibility

    /// The label, the serial number or its placeholder, and the eye button.
    var body: some View {
      let presentation = visibility.presentation(of: serial)
      OJDLabeledRow(label) {
        HStack(spacing: 6) {
          if presentation.isObscured {
            Text(presentation.displayText).foregroundColor(Color(NSColor.secondaryLabelColor))
              .blur(radius: 4).accessibilityHidden(true)
          } else {
            OJDValueText(value: serial).foregroundColor(Color(NSColor.secondaryLabelColor))
              .textSelection(.enabled)
          }
          if presentation.canToggle {
            Button {
              visibility.toggle()
            } label: {
              Image(systemName: presentation.toggleSymbolName)
            }.buttonStyle(.borderless).help(OJDLocalized.string(presentation.toggleLabelKey))
              .ojdAccessibilityLabel(OJDLocalized.string(presentation.toggleLabelKey))
          }
        }
      }.accessibilityElement(children: .contain).ojdAccessibilityValue(presentation.spokenText)
    }
  }

#endif
