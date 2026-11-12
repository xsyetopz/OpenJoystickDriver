#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  extension ControllerReadiness {
    /// The color role of the state's symbol.
    var tone: SemanticTone {
      switch self {
      case .working: return .positive
      case .needsStep: return .attention
      case .notSupported: return .neutral
      }
    }
  }

  /// The symbol and name of a controller's state, shown under its name in the list.
  struct ControllerReadinessMark: View {
    /// The state.
    let readiness: ControllerReadiness

    /// The symbol and the name.
    var body: some View {
      HStack(spacing: OJDSpacing.xxSmall) {
        OJDSystemSymbol(name: readiness.symbolName, fallback: nil).foregroundColor(
          Color(readiness.tone.color)
        ).accessibilityHidden(true)
        Text(OJDLocalized.string(readiness.titleKey))
      }.font(.caption).lineLimit(1)
    }
  }

  /// A controller's state in its detail: the symbol, the name, one sentence and one button.
  struct ControllerReadinessCard: View {
    /// The state.
    let readiness: ControllerReadiness
    /// Runs what the button does.
    let perform: @MainActor (ControllerReadinessAction) -> Void

    /// The symbol, the texts and the button.
    var body: some View {
      HStack(alignment: .center, spacing: OJDSpacing.medium) {
        OJDSystemSymbol(name: readiness.symbolName, fallback: nil).foregroundColor(
          Color(readiness.tone.color)
        ).font(.title2).frame(width: 28).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(OJDLocalized.string(readiness.titleKey)).font(.headline)
          Text(OJDLocalized.string(readiness.messageKey)).font(.callout).foregroundColor(
            Color(NSColor.secondaryLabelColor)
          ).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        Button(OJDLocalized.string(readiness.actionTitleKey)) { perform(readiness.action) }
      }.accessibilityElement(children: .contain).ojdAccessibilityLabel(
        OJDLocalized.string(readiness.titleKey)
      )
    }
  }

#endif
