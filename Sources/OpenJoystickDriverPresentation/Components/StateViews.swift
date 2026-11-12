#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import OpenJoystickDriverKit
  import SwiftUI

  /// The empty detail of a column: centered secondary text, as Mail shows for "No Message
  /// Selected". `ContentUnavailableView` on macOS 14 and later, the same layout built from text
  /// on macOS 12 and 13.
  struct EmptyStateView: View {
    /// The SF Symbol above the title.
    let symbol: String
    /// The headline of the empty state.
    let title: String
    /// The secondary text under the title, or nil for none.
    let message: String?
    /// The title of the button that fills the empty state, or nil for no button.
    let actionTitle: String?
    /// What the button runs.
    let action: (() -> Void)?

    /// Creates the empty state with a symbol, a title, an optional message and an optional action.
    init(
      symbol: String,
      title: String,
      message: String? = nil,
      actionTitle: String? = nil,
      action: (() -> Void)? = nil
    ) {
      self.symbol = symbol
      self.title = title
      self.message = message
      self.actionTitle = actionTitle
      self.action = action
    }

    /// The button that fills the empty state, when an action title and an action are set.
    @ViewBuilder
    private var actionButton: some View {
      if let actionTitle, let action {
        Button(actionTitle, action: action)
      }
    }

    /// The title, the symbol and the message in a placeholder.
    @ViewBuilder
    var body: some View {
      if #available(macOS 14, *) {
        ContentUnavailableView {
          Label(title, systemImage: symbol)
        } description: {
          if let message { Text(message) }
        } actions: {
          actionButton
        }
      } else {
        VStack(spacing: OJDSpacing.xSmall) {
          OJDSystemSymbol(name: symbol, fallback: OJDLocalized.string("term.status")).font(
            .largeTitle
          ).foregroundColor(Color(NSColor.tertiaryLabelColor)).accessibilityHidden(true)
          Text(title).font(.headline).foregroundColor(Color(NSColor.secondaryLabelColor))
          if let message {
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor))
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          }
          actionButton
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  /// A progress indicator beside a message, for an area that is loading.
  struct LoadingStateView: View {
    /// The message beside the indicator.
    let message: String

    /// The progress indicator with the message.
    var body: some View {
      HStack(spacing: OJDSpacing.small) {
        ProgressView()
        Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
      }
    }
  }

  /// A failure with its title, its message and a Try Again button.
  struct ServiceFailureStateView: View {
    /// The failure's title.
    let title: String
    /// The failure's message.
    let message: String
    /// Runs when the user presses Try Again.
    let retry: () -> Void

    /// The failure symbol, the title, the message and Try Again.
    var body: some View {
      GroupBox {
        HStack(alignment: .top, spacing: OJDSpacing.medium) {
          OJDSystemSymbol(
            name: SemanticState.failure.presentation.symbolName,
            fallback: OJDLocalized.string("status.needsAttention")
          ).foregroundColor(Color(SemanticState.failure.presentation.tone.color))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: OJDSpacing.small) {
            Text(title).font(.headline)
            Text(message).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Button(OJDLocalized.string("action.tryAgain"), action: retry)
          }
          Spacer(minLength: 0)
        }.padding(4)
      }.accessibilityElement(children: .contain).ojdAccessibilityLabel(title)
        .ojdAccessibilityValue(message)
    }
  }

#endif
