import Foundation
import OpenJoystickDriverKit

/// What the service did for the output requests sent to one controller.
package struct AutomationOutputResult: Equatable, Sendable {
  /// The session ID of the controller.
  package let controller: String
  /// One entry for each request, in order.
  package let results: [ControllerOutputEntry]
}

extension AutomationService {
  /// Sends each of `requests` to the controller that `controller` names, as `ojd controller
  /// rumble`, `player`, and `light` do, and stops at the first one the controller does not deliver.
  ///
  /// `controller` is a port key, a session token, or a `VVVV:PPPP` model that matches exactly one
  /// connected controller. `requestedMotors` are the motors a rumble request names, so a rumble
  /// that no motor of the controller can run fails.
  ///
  /// - Throws: ``CodedFailure`` with ``ErrorCode/notFound`` when no connected controller or
  ///   several match, and with ``ErrorCode/controllerRequestFailed`` when the controller lacks the
  ///   output or does not deliver it.
  package func sendOutput(
    _ requests: [ControllerOutputRequest],
    to controller: String,
    requestedMotors: [PhysicalRumbleMotor] = []
  ) async throws -> AutomationOutputResult {
    let device = try ControllerReference.device(named: controller, in: await connectedDevices())
    var entries: [ControllerOutputEntry] = []
    for request in requests {
      let result = await sendControllerOutput(request.command, for: .session(device.sessionToken))
      try ControllerOutput.check(result, request, device)
      if case .setRumble = request.command {
        _ = try ControllerOutput.rumbleOutcome(
          requested: requestedMotors,
          result: result,
          device: device
        )
      }
      entries.append(ControllerOutputEntry(request, result))
    }
    return AutomationOutputResult(controller: device.sessionToken.rawValue, results: entries)
  }
}
