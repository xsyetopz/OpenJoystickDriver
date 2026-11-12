import Foundation
import OpenJoystickDriverKit

/// One access the user still has to give, shown in the main window with one sentence and one
/// button.
struct SetupStep: Equatable, Identifiable {
  /// The access that the step asks for.
  enum Kind: Equatable {
    /// A macOS permission of the Access area.
    case permission(AccessPermissionRow.Kind)
    /// Bluetooth, for Switch 2 controllers.
    case bluetooth
  }

  /// The access.
  let kind: Kind
  /// The localization key of the one sentence of the step.
  let sentenceKey: String
  /// The localization key of the one button of the step.
  let buttonKey: String

  /// The identity of the step, which is its access.
  var id: String {
    switch kind {
    case .permission(let permission): return permission.rawValue
    case .bluetooth: return "bluetooth"
    }
  }
}

/// The setup steps of the main window.
enum SetupSteps {
  /// The steps still open, in the order of the Access area.
  ///
  /// The permissions are the ones the Access area counts as missing. A Bluetooth access that macOS
  /// restricts, or that the service does not report, is no step, because the user cannot act on it.
  /// Input Inject and Post Event both ask for Accessibility, so they are one step, the Input
  /// Inject one, whose button requests both.
  static func open(
    permissionState: RuntimePermissionLoadState,
    statusState: RuntimeStatusState
  ) -> [SetupStep] {
    var missing = AccessReadiness.missingPermissions(
      permissionState: permissionState,
      statusState: statusState
    )
    if missing.contains(.inputInject) { missing.removeAll { $0 == .postEvent } }
    var steps = missing.map { kind in
      SetupStep(
        kind: .permission(kind),
        sentenceKey: sentenceKey(for: kind),
        buttonKey: "action.request"
      )
    }
    if case .available(let status) = statusState, let bluetooth = status.bluetoothAccess,
      bluetooth.needsStep
    {
      steps.append(
        SetupStep(
          kind: .bluetooth,
          sentenceKey: "ui.setupSteps.bluetooth",
          buttonKey: bluetooth == .notAsked
            ? "action.request" : "platform.macos.ui.setup.openSystemSettings"
        )
      )
    }
    return steps
  }

  /// The localization key of the sentence of a permission step.
  private static func sentenceKey(for kind: AccessPermissionRow.Kind) -> String {
    switch kind {
    case .inputRead: return "platform.macos.ui.setupSteps.inputRead"
    case .inputInject: return "platform.macos.ui.setupSteps.inputInject"
    case .postEvent: return "platform.macos.ui.setupSteps.postEvent"
    case .notification: preconditionFailure("A notification setting is never a setup step")
    }
  }
}

/// Decides whether the main window shows the setup steps: only when the first load of the status
/// found a step open, and until the user continues or no step is left.
struct SetupStepsGate: Equatable {
  /// Whether the first load found a step open; nil before the first load.
  private var openAtStart: Bool?
  /// Whether the user chose to continue.
  private var dismissed = false
  /// Whether a step is open now.
  private var hasOpenStep = false

  /// Whether the setup steps show.
  var isShown: Bool { openAtStart == true && !dismissed && hasOpenStep }

  /// Records the state of a load; the first loaded one fixes whether the app started with a step
  /// open.
  mutating func update(loaded: Bool, openSteps: Int) {
    guard loaded else { return }
    if openAtStart == nil { openAtStart = openSteps > 0 }
    hasOpenStep = openSteps > 0
  }

  /// Hides the steps for the rest of the run.
  mutating func dismiss() { dismissed = true }
}
