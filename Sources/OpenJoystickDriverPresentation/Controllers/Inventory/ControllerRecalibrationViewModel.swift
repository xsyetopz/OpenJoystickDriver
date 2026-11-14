#if canImport(SwiftUI)
  import Combine
  import Foundation
  import OpenJoystickDriverKit

  /// The state of the recalibration controls: whether a step runs and the text of its result.
  @MainActor
  final class ControllerRecalibrationViewModel: ObservableObject {
    /// The text of the latest result or failure, or nil.
    @Published
    private(set) var message: String?
    /// Whether `message` reports a failure.
    @Published
    private(set) var isFailure = false
    /// Whether a step or a reset runs.
    @Published
    private(set) var isBusy = false
    /// The gateway to the service.
    private let gateway: any ControllerRecalibrationGateway

    /// Creates the model on `gateway`.
    ///
    /// - Parameter gateway: The gateway to the service.
    init(gateway: any ControllerRecalibrationGateway) { self.gateway = gateway }

    /// Runs `action` on the controller and shows what it stored, what did not move, or why it
    /// failed.
    ///
    /// One request runs at a time.
    ///
    /// - Parameters:
    ///   - action: The step to run, or the reset.
    ///   - selector: The controller.
    func run(_ action: ControllerRecalibrationAction, for selector: ControllerReference) async {
      guard !isBusy else { return }
      isBusy = true
      message = nil
      isFailure = false
      do {
        let result = try await gateway.recalibrateController(selector, action: action)
        if let failure = result.failure {
          show(Self.text(of: failure, detail: result.detail), failed: true)
        } else {
          show(Self.text(of: result), failed: false)
        }
      } catch { show(RuntimePresentation.userFacingError(error), failed: true) }
      isBusy = false
    }

    /// Sets the message and whether it is a failure.
    private func show(_ text: String, failed: Bool) {
      message = text
      isFailure = failed
    }

    /// The text of a result that stored or cleared values.
    private static func text(of result: ControllerRecalibrationResult) -> String {
      if result.action == .reset {
        return OJDLocalized.string(
          result.gyroOffsetCleared
            ? "ui.controllers.recalibrate.resetDoneGyro" : "ui.controllers.recalibrate.resetDone"
        )
      }
      var parts: [String] = []
      if !result.stored.values.isEmpty {
        parts.append(OJDLocalized.string("ui.controllers.recalibrate.stored"))
      }
      let unmoved = ControllerCalibrationRow.Control.allCases.filter {
        result.unmoved.contains(where: $0.covers)
      }
      if !unmoved.isEmpty {
        parts.append(
          OJDLocalized.formatted(
            "ui.controllers.recalibrate.unmoved",
            unmoved.map(ControllerCalibrationSection.label).joined(separator: ", ")
          )
        )
      }
      return parts.joined(separator: " ")
    }

    /// The text of a refusal, followed by the detail of the service when it has one.
    private static func text(of failure: ControllerRecalibrationFailure, detail: String?) -> String
    {
      let reason: String
      switch failure {
      case .controllerUnavailable:
        reason = OJDLocalized.string("ui.motion.calibration.controllerUnavailable")
      case .noRecord: reason = OJDLocalized.string("ui.controllers.server.noRecord")
      case .invalidRecord: reason = OJDLocalized.string("ui.controllers.server.invalidRecord")
      case .persistenceFailed:
        reason = OJDLocalized.string("ui.controllers.server.persistenceFailed")
      }
      return [reason, detail].compactMap { $0 }.joined(separator: " ")
    }
  }

  extension ControllerCalibrationRow.Control {
    /// Whether `control` is this stick, one of its axes, or this trigger.
    fileprivate func covers(_ control: OpenJoystickDriverKit.Control) -> Bool {
      switch (self, control) {
      case (.leftStick, .leftStickX), (.leftStick, .leftStickY), (.rightStick, .rightStickX),
        (.rightStick, .rightStickY), (.leftTrigger, .leftTrigger), (.rightTrigger, .rightTrigger):
        true
      default: false
      }
    }
  }
#endif
