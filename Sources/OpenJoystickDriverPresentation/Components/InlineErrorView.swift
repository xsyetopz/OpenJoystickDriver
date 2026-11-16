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
    /// The tooltip of the Details control.
    let detailsHelp: String
    /// The title of the action button.
    let actionTitle: String
    /// The tooltip of the action button.
    let actionHelp: String
    /// Runs when the user presses the action button.
    let action: () -> Void
    /// The title of a second action button, or nil for none.
    var secondaryActionTitle: String?
    /// Runs when the user presses the second action button.
    var secondaryAction: (() -> Void)?
    /// Whether the explanation of the code is open.
    @State
    private var showsDetails = false

    /// The failure symbol and message in a group box, with the action button.
    var body: some View {
      GroupBox {
        VStack(alignment: .leading, spacing: OJDSpacing.small) {
          HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.medium) {
            OJDSystemSymbol(
              name: SemanticState.failure.presentation.symbolName,
              fallback: OJDLocalized.string("status.needsAttention")
            ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
              .accessibilityHidden(true)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if code != nil {
              Button(detailsTitle) { showsDetails.toggle() }
                .help(detailsHelp)
            }
            if let secondaryActionTitle, let secondaryAction {
              Button(secondaryActionTitle, action: secondaryAction)
                .help(OJDLocalized.string("ui.help.migrate"))
            }
            Button(actionTitle, action: action).help(actionHelp)
          }
          if showsDetails, let code {
            VStack(alignment: .leading, spacing: OJDSpacing.xSmall) {
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
