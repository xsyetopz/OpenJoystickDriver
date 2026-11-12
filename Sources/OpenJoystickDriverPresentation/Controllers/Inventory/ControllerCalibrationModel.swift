import Combine
import Foundation
import OpenJoystickDriverKit

/// Reads the raw and tuned values of one controller for the calibration view.
@MainActor
final class ControllerCalibrationModel: ObservableObject {
  /// The rows of the last read; empty while the service has reported no input.
  @Published
  private(set) var rows: [ControllerCalibrationRow] = []

  /// Reads the input and the virtual gamepad values of `device` once.
  ///
  /// A failed read keeps the rows of the last one.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - deadZone: The stick dead zone of the controller's model, or nil while none is set.
  ///   - gateway: The service requests.
  func refresh(
    device: ApplicationServiceDeviceDescription,
    deadZone: Double?,
    gateway: any ControllerDiagnosticsGateway
  ) async {
    let selector = ControllerReference.session(device.sessionToken)
    do {
      async let input = gateway.controllerState(for: selector)
      async let output = gateway.virtualOutputState(for: selector)
      let (nextInput, nextOutput) = try await (input, output)
      rows =
        nextInput.map {
          ControllerCalibrationRows.rows(input: $0, output: nextOutput, deadZone: deadZone)
        } ?? []
    } catch { return }
  }

  /// Reads every `interval` until the task is cancelled.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - deadZone: Returns the stick dead zone of the controller's model, or nil while none is set.
  ///   - gateway: The service requests.
  ///   - interval: The nanoseconds between two reads.
  func run(
    device: ApplicationServiceDeviceDescription,
    deadZone: @MainActor () -> Double?,
    gateway: any ControllerDiagnosticsGateway,
    interval: UInt64 = 100_000_000
  ) async {
    while !Task.isCancelled {
      await refresh(device: device, deadZone: deadZone(), gateway: gateway)
      do { try await Task.sleep(nanoseconds: interval) } catch { return }
    }
  }
}
