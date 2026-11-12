#if canImport(SwiftUI)

  import AppKit
  import Foundation
  import SwiftUI

  /// The main window's setup steps: one sentence and one button for each access still open.
  ///
  /// Nothing is requested until the user presses the button of a step.
  struct SetupStepsView: View {
    /// The steps still open.
    let steps: [SetupStep]
    /// Runs the step whose button the user pressed.
    let perform: @MainActor (SetupStep) -> Void
    /// Leaves the steps for the selected area.
    let finish: @MainActor () -> Void

    /// The title, the steps and the button that leaves them.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.large) {
        Text(OJDLocalized.string("ui.setupSteps.title")).font(.title2.weight(.semibold))
          .accessibilityAddTraits(.isHeader)
        ForEach(steps) { step in
          HStack(alignment: .firstTextBaseline, spacing: OJDSpacing.medium) {
            Text(OJDLocalized.string(step.sentenceKey)).fixedSize(
              horizontal: false,
              vertical: true
            )
            Spacer(minLength: OJDSpacing.medium)
            Button(OJDLocalized.string(step.buttonKey)) { perform(step) }
              .ojdAccessibilityLabel(OJDLocalized.string(step.sentenceKey))
          }
        }
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.done"), action: finish)
            .keyboardShortcut(.defaultAction)
        }
      }.padding(OJDSpacing.large).frame(maxWidth: 560, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity)
    }
  }

#endif
