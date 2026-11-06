#if canImport(SwiftUI)

  import AppKit
  import SwiftUI

  /// The strip under the toolbar that lists what stops controllers from working.
  ///
  /// It exists only while `MainWindowProblem.current` returns problems.
  struct MainWindowProblemBanner: View {
    /// The problems to list, most blocking first.
    let problems: [MainWindowProblem]
    /// Runs the fix that a row's button offers.
    let perform: @MainActor (MainWindowProblemAction) -> Void

    /// The rows of the problems, or nothing while there is no problem.
    var body: some View {
      if !problems.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(problems) { problem in
            row(problem)
            if problem != problems.last { Divider().padding(.leading, 44) }
          }
          Divider()
        }.background(Color(tone.color).opacity(0.10))
      }
    }

    /// Red when any problem is a failure, else orange.
    private var tone: SemanticTone { problems.contains(where: \.isFailure) ? .failure : .attention }

    /// Returns the banner row for `problem`: a symbol, the title, the detail and its button.
    private func row(_ problem: MainWindowProblem) -> some View {
      let state: SemanticState = problem.isFailure ? .failure : .attention
      let title = OJDLocalized.string(problem.titleKey)
      let detail = detailText(problem)
      return HStack(alignment: .center, spacing: 10) {
        OJDSystemSymbol(name: state.presentation.symbolName + ".fill", fallback: nil)
          .foregroundColor(Color(state.presentation.tone.color)).font(.body)
          .frame(width: 22).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.body.weight(.semibold))
          Text(detail).font(.callout).foregroundColor(Color(NSColor.secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        if let action = problem.action {
          Button(OJDLocalized.string(action.titleKey)) { perform(action) }
        }
      }.padding(.horizontal, 12).padding(.vertical, 8).accessibilityElement(children: .combine)
        .ojdAccessibilityLabel(title).ojdAccessibilityValue(detail)
    }

    /// Returns the service's own message for a service problem, else the localized detail.
    private func detailText(_ problem: MainWindowProblem) -> String {
      if case .serviceUnavailable(let message) = problem { return message }
      if case .listenerStopped(let message) = problem { return message }
      guard let key = problem.detailKey else { return "" }
      return OJDLocalized.string(key)
    }
  }

#endif
