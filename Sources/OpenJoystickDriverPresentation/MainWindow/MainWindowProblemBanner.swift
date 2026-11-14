#if canImport(SwiftUI)

  import OpenJoystickDriverKit
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
        VStack(alignment: .leading, spacing: OJDSpacing.none) {
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
      let title = problem.title
      let detail = detailText(problem)
      return HStack(alignment: .center, spacing: OJDSpacing.medium) {
        if case .service(let readiness, let message) = problem {
          ServiceReadinessRow(readiness: readiness, detail: message)
        } else {
          OJDSystemSymbol(name: state.presentation.symbolName + ".fill", fallback: nil)
            .foregroundColor(Color(state.presentation.tone.color)).font(.body)
            .frame(width: 22).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: OJDSpacing.xxSmall) {
            Text(title).font(.body.weight(.semibold))
            Text(detail).font(.callout).foregroundColor(Color(NSColor.secondaryLabelColor))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 12)
        if let action = problem.action, let titleKey = problem.actionTitleKey {
          Button(OJDLocalized.string(titleKey)) { perform(action) }.disabled(
            !problem.isActionEnabled
          )
        }
      }.padding(.horizontal, 12).padding(.vertical, 8).accessibilityElement(children: .combine)
        .ojdAccessibilityLabel(title).ojdAccessibilityValue(detail)
    }

    /// Returns the service's own message for a service problem, else the localized detail.
    private func detailText(_ problem: MainWindowProblem) -> String {
      if case .service(_, let message) = problem { return message }
      if case .virtualProfileStore(let message) = problem { return message }
      guard let key = problem.detailKey else { return "" }
      if case .driver(.failed(let failure), _) = problem {
        return OJDLocalized.formatted(key, failure.domain, failure.code, failure.text)
      }
      return OJDLocalized.string(key)
    }
  }

#endif
