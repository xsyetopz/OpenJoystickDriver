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
  /// A failed read keeps the rows of the last one, and a read with the same rows publishes nothing,
  /// so a controller at rest does not redraw the view.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - deadZone: The stick dead zone of the controller's model, or nil while none is set.
  ///   - gateway: The service requests.
  /// - Returns: Whether the rows changed.
  @discardableResult
  func refresh(
    device: ApplicationServiceDeviceDescription,
    deadZone: Double?,
    gateway: any ControllerDiagnosticsGateway
  ) async -> Bool {
    let selector = ControllerReference.session(device.sessionToken)
    do {
      async let input = gateway.controllerState(for: selector)
      async let output = gateway.virtualOutputState(for: selector)
      let (nextInput, nextOutput) = try await (input, output)
      let next =
        nextInput.map {
          ControllerCalibrationRows.rows(input: $0, output: nextOutput, deadZone: deadZone)
        } ?? []
      guard next != rows else { return false }
      rows = next
      return true
    } catch { return false }
  }

  /// Reads until the task is cancelled, every `fastest` nanoseconds while the values move.
  ///
  /// Each read with unchanged rows doubles the wait up to `slowest`, and a changed read returns it
  /// to `fastest`. A controller at rest costs the service a few reads a second instead of ten, and
  /// a moved stick shows within `slowest`.
  ///
  /// - Parameters:
  ///   - device: The controller.
  ///   - deadZone: Returns the stick dead zone of the controller's model, or nil while none is set.
  ///   - gateway: The service requests.
  ///   - fastest: The nanoseconds between two reads while the values change.
  ///   - slowest: The longest nanoseconds between two reads while the values stay the same.
  ///   - sleep: Waits the given nanoseconds; throws when the task is cancelled.
  func run(
    device: ApplicationServiceDeviceDescription,
    deadZone: @MainActor () -> Double?,
    gateway: any ControllerDiagnosticsGateway,
    fastest: UInt64 = 100_000_000,
    slowest: UInt64 = 500_000_000,
    sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
  ) async {
    var interval = fastest
    while !Task.isCancelled {
      let changed = await refresh(device: device, deadZone: deadZone(), gateway: gateway)
      interval = Self.nextInterval(
        after: interval,
        changed: changed,
        fastest: fastest,
        slowest: slowest
      )
      do { try await sleep(interval) } catch { return }
    }
  }

  /// Returns the wait before the next read: `fastest` after a change, else twice `current` up to
  /// `slowest`.
  static func nextInterval(
    after current: UInt64,
    changed: Bool,
    fastest: UInt64,
    slowest: UInt64
  ) -> UInt64 {
    guard !changed else { return fastest }
    let doubled = current.multipliedReportingOverflow(by: 2)
    return doubled.overflow ? slowest : min(slowest, max(fastest, doubled.partialValue))
  }
}
