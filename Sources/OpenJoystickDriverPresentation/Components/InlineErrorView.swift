#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The error pattern of the main window: a symbol, the message, and a Details control that
  /// shows the `ojd explain` text of the error code.
  struct InlineErrorView: View {
    /// The error message.
    let message: String
    /// The error code that Details explains, or nil for no Details control.
    let code: ErrorCode?
    /// The title of the Details control.
    let detailsTitle: String
    /// The VoiceOver label of the Details control.
    let detailsAccessibilityLabel: String
    /// The title of the action button.
    let actionTitle: String
    /// The VoiceOver label of the action button.
    let actionAccessibilityLabel: String
    /// Runs when the user presses the action button.
    let action: () -> Void
    /// Whether the explanation of the code is open.
    @State
    private var showsDetails = false

    /// The failure symbol and message in a group box, with the action button.
    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: 8) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("status.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
              .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if code != nil {
              Button(detailsTitle) { showsDetails.toggle() }
                .ojdAccessibilityLabel(detailsAccessibilityLabel)
            }
            Button(actionTitle, action: action).ojdAccessibilityLabel(actionAccessibilityLabel)
          }
          if showsDetails, let code {
            VStack(alignment: .leading, spacing: 4) {
              Text(code.rawValue).font(.caption.weight(.semibold))
              Text(code.localizedExplanation).font(.caption).foregroundColor(
                Color(NSColor.secondaryLabelColor)
              ).fixedSize(horizontal: false, vertical: true)
            }.textSelection(.enabled)
          }
        }.padding(4)
      }.accessibilityElement(children: .contain).ojdAccessibilityLabel(message)
    }
  }

#endif
