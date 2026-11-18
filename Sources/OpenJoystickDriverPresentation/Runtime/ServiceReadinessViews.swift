#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  extension ServiceReadiness {
    /// The color role of the state's symbol.
    var tone: SemanticTone {
      switch self {
      case .running: return .positive
      case .needsApproval, .versionMismatch: return .attention
      case .stopped, .listenerStopped, .readFailed, .notInstalled: return .failure
      case .checking: return .neutral
      }
    }
  }

  /// The symbol and sentence of the service's state, with the service's own message under it when
  /// it gave one.
  struct ServiceReadinessRow: View {
    /// The state.
    let readiness: ServiceReadiness
    /// What the service said about the state; empty when it said nothing.
    let detail: String

    /// The symbol, the sentence and the detail.
    var body: some View {
      HStack(alignment: .center, spacing: OJDSpacing.medium) {
        OJDSystemSymbol(name: readiness.symbolName, fallback: nil).foregroundColor(
          Color(readiness.tone.color)
        ).font(.body).frame(width: 22).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
          Text(OJDLocalized.string(readiness.messageKey)).font(.body.weight(.semibold))
          if !detail.isEmpty {
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(
              horizontal: false,
              vertical: true
            )
          }
        }
      }.accessibilityElement(children: .combine)
    }
  }

#endif
