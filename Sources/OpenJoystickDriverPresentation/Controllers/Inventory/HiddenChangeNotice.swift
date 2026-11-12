#if canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  /// The row of a Simple view that tells the person a setting they cannot see is changed, or the
  /// placeholder of an area the Simple interface hides, with a button that switches the interface
  /// to Advanced.
  struct HiddenChangeNotice: View {
    /// What the row says.
    enum Content: Equatable {
      /// This many hidden controls hold a value other than their default.
      case changed(Int)
      /// Every row of the area is Advanced.
      case needsAdvanced

      /// Whether the row shows at `level`.
      ///
      /// - Parameter level: The interface level.
      /// - Returns: Whether the row shows at `level`.
      func isShown(at level: InterfaceLevel) -> Bool {
        guard level == .simple else { return false }
        switch self {
        case .changed(let count): return count > 0
        case .needsAdvanced: return true
        }
      }

      /// The localized sentence of the row.
      var message: String {
        switch self {
        case .changed(let count):
          return OJDLocalized.plural("ui.interface.hiddenChanges", count: count)
        case .needsAdvanced: return OJDLocalized.string("ui.interface.areaNeedsAdvanced")
        }
      }
    }

    /// What the row says.
    let content: Content
    /// The interface level.
    @Environment(\.ojdInterfaceLevel)
    private var level
    /// The preferences that store the interface level.
    @Environment(\.ojdPreferences)
    private var preferences

    /// The sentence and the button, or nothing when the row does not show: a row for a changed
    /// hidden setting, and a placeholder filling the column for an area that is all Advanced.
    @ViewBuilder
    var body: some View {
      if content.isShown(at: level) {
        switch content {
        case .changed:
          HStack(spacing: OJDSpacing.medium) {
            Text(content.message).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(showAllControls, action: showAdvanced)
          }.padding(.vertical, OJDSpacing.small)
        case .needsAdvanced:
          EmptyStateView(
            symbol: "eye.slash",
            title: content.message,
            actionTitle: showAllControls,
            action: showAdvanced
          )
        }
      }
    }

    /// The title of the button that switches the interface to Advanced.
    private var showAllControls: String { OJDLocalized.string("ui.interface.showAdvanced") }

    /// Switches the interface to Advanced.
    private func showAdvanced() { preferences?.setInterfaceLevel(.advanced) }
  }

#endif
