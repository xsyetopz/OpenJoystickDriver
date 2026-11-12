import Foundation
import OpenJoystickDriverKit

/// What a person reads about a connected controller: it works, it waits for a step from them, or
/// OJD cannot use it yet.
enum ControllerReadiness: Equatable, Sendable {
  /// The step that the user takes for a controller in the ``needsStep(_:)`` state.
  enum Step: Equatable, Sendable {
    /// A permission the app needs is missing; the Access area holds the step.
    case grantAccess
    /// The Xbox USB driver extension must be approved, claimed or repaired.
    case setUpDriver
    /// The controller's own next step, such as closing another program; its detail says which.
    case otherStep
  }

  /// The controller works.
  case working
  /// The controller needs a step from the user.
  case needsStep(Step)
  /// OJD has no support for the controller.
  case notSupported

  /// The SF Symbol of the state; the three shapes are a circle, a triangle and a diamond, so the
  /// states differ without color.
  var symbolName: String {
    switch self {
    case .working: return "checkmark.circle.fill"
    case .needsStep: return "exclamationmark.triangle.fill"
    case .notSupported: return "questionmark.diamond.fill"
    }
  }

  /// The localization key of the state's name.
  var titleKey: String {
    switch self {
    case .working: return "ui.controllers.readiness.working.title"
    case .needsStep: return "ui.controllers.readiness.needsStep.title"
    case .notSupported: return "ui.controllers.readiness.notSupported.title"
    }
  }

  /// The localization key of the one sentence that says what the state means.
  var messageKey: String {
    switch self {
    case .working: return "ui.controllers.readiness.working.message"
    case .needsStep(.grantAccess): return "ui.controllers.readiness.needsStep.access.message"
    case .needsStep(.setUpDriver): return "ui.controllers.readiness.needsStep.driver.message"
    case .needsStep(.otherStep): return "ui.controllers.readiness.needsStep.other.message"
    case .notSupported: return "ui.controllers.readiness.notSupported.message"
    }
  }

  /// The localization key of the one button's title.
  var actionTitleKey: String {
    switch self {
    case .working: return "ui.controllers.readiness.working.action"
    case .needsStep(.grantAccess): return "ui.controllers.readiness.needsStep.access.action"
    case .needsStep(.setUpDriver): return "ui.controllers.readiness.needsStep.driver.action"
    case .needsStep(.otherStep): return "ui.controllers.readiness.needsStep.other.action"
    case .notSupported: return "ui.controllers.readiness.notSupported.action"
    }
  }

  /// What the one button does.
  var action: ControllerReadinessAction {
    switch self {
    case .working: return .openInputTest
    case .needsStep(.grantAccess): return .openAccess
    case .needsStep(.setUpDriver): return .setUpDriver
    case .needsStep(.otherStep): return .openTroubleshooting
    case .notSupported: return .openSupportedControllers
    }
  }
}

/// What the button of a ``ControllerReadiness`` does.
enum ControllerReadinessAction: Equatable, Sendable {
  /// Opens the Input Test window for the controller.
  case openInputTest
  /// Opens the Access area.
  case openAccess
  /// Approves, claims or repairs the driver extension.
  case setUpDriver
  /// Opens the wiki page `Troubleshooting`.
  case openTroubleshooting
  /// Opens the wiki page `Supported-Controllers`.
  case openSupportedControllers

  /// The wiki page that the action opens; nil for an action that opens none.
  var wikiPage: String? {
    switch self {
    case .openSupportedControllers: return "Supported-Controllers"
    case .openTroubleshooting: return MainWindowArea.activity.wikiPage
    case .openInputTest, .openAccess, .setUpDriver: return nil
    }
  }

  /// The address of ``wikiPage`` on the project's wiki; nil for an action that opens none.
  var wikiURL: URL? {
    wikiPage.flatMap { URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/wiki/\($0)") }
  }
}

/// The facts of one listed controller that decide its ``ControllerReadiness``.
struct ControllerReadinessInput: Equatable, Sendable {
  /// What kind of row the controller is.
  enum Subject: Equatable, Sendable {
    /// OJD reads the controller and serves it by this route.
    case served(ServingRoute)
    /// OJD sees the controller with no protocol bound, for this reason.
    case unserved(ProtocolBindingReason)
  }

  /// The row kind and its route or reason.
  let subject: Subject
  /// Whether a permission the app needs is missing.
  let isPermissionMissing: Bool
  /// Whether the controller's route needs the driver extension to be set up first.
  let needsDriverStep: Bool

  /// Creates the input from its facts.
  init(subject: Subject, isPermissionMissing: Bool = false, needsDriverStep: Bool = false) {
    self.subject = subject
    self.isPermissionMissing = isPermissionMissing
    self.needsDriverStep = needsDriverStep
  }

  /// Creates the input of a connected controller that OJD serves.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - isPermissionMissing: Whether a permission the app needs is missing.
  ///   - driver: The state of the driver extension.
  init(
    device: ApplicationServiceDeviceDescription,
    isPermissionMissing: Bool,
    driver: SystemExtensionSetupState
  ) {
    let extensionNotReady: Bool
    switch driver {
    case .active, .checking: extensionNotReady = false
    case .missingEmbedded, .invalid, .unavailable, .needsActivation, .replacementNeeded, .running,
      .needsApproval, .cancelled, .timedOut, .failed:
      extensionNotReady = true
    }
    self.init(
      subject: .served(device.servingDecision.route),
      isPermissionMissing: isPermissionMissing,
      needsDriverStep: device.isHeldByAppleDriver
        || (device.physicalOwnership == .extensionOwnedUSB && extensionNotReady)
    )
  }
}

extension ControllerReadiness {
  /// Returns the state of a controller.
  ///
  /// A controller that no persona or record covers is not supported, whatever else is missing. A
  /// controller that waits for the driver comes before one that waits for a permission, the order
  /// of the problem banner. Every other served controller works, including one whose output the
  /// user turned off or another virtual device stands for.
  ///
  /// - Parameter input: The facts of the controller.
  /// - Returns: The state to show.
  static func resolve(_ input: ControllerReadinessInput) -> Self {
    switch input.subject {
    case .unserved(let reason):
      switch reason {
      case .noProtocolMatch, .ambiguousProtocolMatch, .interfaceContractMismatch,
        .descriptorContractMismatch, .unsupportedProtocolVariant, .unsupportedTransportVariant,
        .virtualProfileUnavailable, .noModeMatched:
        return .notSupported
      case .deviceInUse, .configurationUnreadable, .bootloaderIdentity, .noControllerLinked:
        return .needsStep(.otherStep)
      }
    case .served(let route):
      if case .outputDisabled(.noVirtualProfile) = route { return .notSupported }
      if input.needsDriverStep { return .needsStep(.setUpDriver) }
      if input.isPermissionMissing { return .needsStep(.grantAccess) }
      return .working
    }
  }
}
