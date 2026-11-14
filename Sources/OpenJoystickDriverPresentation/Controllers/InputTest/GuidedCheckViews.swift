#if canImport(AppKit) && canImport(SwiftUI)

  import AppKit
  import OpenJoystickDriverKit
  import SwiftUI

  extension RuntimePresentation {
    /// Returns the label of a control a guided check names, by its document name.
    ///
    /// - Parameter id: A `Control` raw value, `LeftStick` or `RightStick`.
    /// - Returns: The label of the control.
    static func guidedCheckLabel(_ id: String) -> String {
      switch id {
      case "LeftStick": return OJDLocalized.string("ui.inputTest.guidedCheck.leftStick")
      case "RightStick": return OJDLocalized.string("ui.inputTest.guidedCheck.rightStick")
      case Control.leftTrigger.rawValue: return axisLabel(.leftTrigger)
      case Control.rightTrigger.rawValue: return axisLabel(.rightTrigger)
      default: return Control(rawValue: id).map(buttonLabel) ?? id
      }
    }
  }

  /// The Guided Check button of Input Test, the text of the running step with its Skip button, and
  /// the sheets of the finished check.
  struct GuidedCheckRow: View {
    /// The state of the check.
    @ObservedObject
    var check: GuidedCheckModel
    /// Whether the check can start.
    let canStart: Bool
    /// Starts the check.
    let start: () -> Void

    /// The step, or the button that starts a check.
    var body: some View {
      HStack(spacing: OJDSpacing.small) {
        if let run = check.run, let current = run.current {
          GuidedCheckStepView(
            text: OJDLocalized.formatted(
              "ui.inputTest.guidedCheck.step",
              run.results.count + 1,
              run.controls.count,
              RuntimePresentation.guidedCheckLabel(current.id)
            ),
            skip: check.skip
          )
        } else {
          Button(OJDLocalized.string("ui.inputTest.guidedCheck.start"), action: start)
            .disabled(!canStart)
          Spacer()
        }
      }.sheet(isPresented: $check.isEndSheetPresented) { GuidedCheckEndSheet(check: check) }
    }
  }

  /// The text of one step and its Skip button.
  struct GuidedCheckStepView: View {
    /// What to move.
    let text: String
    /// Ends the step as skipped.
    let skip: () -> Void

    /// The text and the button.
    var body: some View {
      HStack(spacing: OJDSpacing.medium) {
        Text(text).font(.headline).fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button(OJDLocalized.string("ui.inputTest.guidedCheck.skip"), action: skip)
      }
    }
  }

  /// The sheet that shows what each control did, with Save, Copy, Open Issue and, after a check in
  /// which every control responded, Validate.
  struct GuidedCheckEndSheet: View {
    /// The state of the check.
    @ObservedObject
    var check: GuidedCheckModel

    /// The result of each step and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(OJDLocalized.string("ui.inputTest.guidedCheck.title")).font(.headline)
        if let result = check.result {
          Text(
            OJDLocalized.formatted(
              "ui.inputTest.guidedCheck.summary",
              result.steps.count { $0.outcome == .responded },
              result.steps.count
            )
          ).foregroundColor(Color(NSColor.secondaryLabelColor))
          ForEach(Array(result.steps.enumerated()), id: \.offset) { _, step in
            HStack {
              Text(RuntimePresentation.guidedCheckLabel(step.control))
              Spacer()
              Text(Self.outcome(step)).foregroundColor(Color(NSColor.secondaryLabelColor))
            }
          }
        }
        if let failure = check.failure {
          Text(failure).foregroundColor(Color(SemanticTone.failure.color)).fixedSize(
            horizontal: false,
            vertical: true
          )
        }
        HStack {
          Button(OJDLocalized.string("action.save")) { check.save() }
          Button(OJDLocalized.string("ui.inputTest.guidedCheck.copy")) { check.copy() }
          Button(OJDLocalized.string("ui.inputTest.guidedCheck.openIssue")) { check.openIssue() }
          if check.validationText != nil {
            Button(OJDLocalized.string("ui.inputTest.guidedCheck.validate")) {
              check.isValidationPresented = true
            }
          }
          Spacer()
          Button(OJDLocalized.string("action.done")) { check.isEndSheetPresented = false }
            .keyboardShortcut(.defaultAction)
        }
      }.ojdSheet(.regular).sheet(isPresented: $check.isValidationPresented) {
        GuidedCheckValidationSheet(check: check)
      }
    }

    /// Returns what happened to `step`, in words.
    static func outcome(_ step: ControllerCheck.Step) -> String {
      switch step.outcome {
      case .responded: OJDLocalized.string("ui.inputTest.guidedCheck.responded")
      case .skipped: OJDLocalized.string("ui.inputTest.guidedCheck.skipped")
      case .otherControl:
        OJDLocalized.formatted(
          "ui.inputTest.guidedCheck.otherControl",
          RuntimePresentation.guidedCheckLabel(step.otherControl ?? "")
        )
      }
    }
  }

  /// The sheet that shows the whole text of a validation and where it goes, before Confirm opens
  /// the prefilled form.
  struct GuidedCheckValidationSheet: View {
    /// The state of the check.
    @ObservedObject
    var check: GuidedCheckModel

    /// The text, the destination and the buttons.
    var body: some View {
      VStack(alignment: .leading, spacing: OJDSpacing.medium) {
        Text(OJDLocalized.string("ui.inputTest.guidedCheck.validate")).font(.headline)
        Text(
          OJDLocalized.formatted(
            "ui.inputTest.guidedCheck.validateText",
            ControllerCheckIssue.destination
          )
        ).foregroundColor(Color(NSColor.secondaryLabelColor)).fixedSize(
          horizontal: false,
          vertical: true
        )
        Text(check.validationText ?? "").font(.system(.body, design: .monospaced))
          .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          Button(OJDLocalized.string("action.cancel")) { check.isValidationPresented = false }
            .keyboardShortcut(.cancelAction)
          Button(OJDLocalized.string("ui.inputTest.guidedCheck.confirm")) {
            check.confirmValidation()
          }.keyboardShortcut(.defaultAction)
        }
      }.ojdSheet(.regular)
    }
  }

#endif
