#if canImport(SwiftUI)
  import Combine
  import Foundation
  import SwiftUI
  import OpenJoystickDriverKit

  /// What the Motion calibration needs from the service: the calibration status of a controller,
  /// or the result of a calibration command.
  protocol MotionCalibrationGateway: Sendable {
    /// Returns the calibration status after the optional command.
    ///
    /// - Parameters:
    ///   - selector: The controller.
    ///   - command: The command to send, or nil to only read the status.
    /// - Returns: The calibration status after the optional command.
    /// - Throws: The error of the request.
    func motionCalibration(
      for selector: ControllerReference,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus
  }

  /// The state of the Motion calibration: the status of the selected controller, the error and
  /// whether a command runs.
  @MainActor
  final class MotionCalibrationViewModel: ObservableObject {
    /// The calibration status of the selected controller, or nil when it is not loaded.
    @Published
    private(set) var status: RemappingMotionCalibrationStatus?
    /// The message of the latest failure, or nil.
    @Published
    private(set) var errorMessage: String?
    /// Whether a command runs.
    @Published
    private(set) var isBusy = false
    /// The selected controller, or nil.
    @Published
    private(set) var selector: ControllerReference?
    /// The gateway to the service.
    private let gateway: any MotionCalibrationGateway
    /// Names the selection; an answer for an earlier selection is dropped.
    private var generation: UInt64 = 0
    /// Counts commands.
    ///
    /// A read that started before a command ended its answer is stale.
    private var commandSequence: UInt64 = 0

    /// Creates the model on `gateway`.
    ///
    /// - Parameter gateway: The gateway to the service.
    init(gateway: any MotionCalibrationGateway) { self.gateway = gateway }

    /// Selects the controller, or none; a different selection clears the status and the error.
    ///
    /// - Parameter selector: The controller, or nil.
    func select(_ selector: ControllerReference?) {
      guard self.selector != selector else { return }
      generation &+= 1
      self.selector = selector
      status = nil
      errorMessage = nil
      isBusy = false
    }

    /// Reads the status without marking the model busy, so controls stay usable.
    ///
    /// A command that starts or ends while the read runs makes its answer stale, and it is dropped.
    func refresh() async {
      guard let selector else { return }
      let requestGeneration = generation
      let requestSequence = commandSequence
      func isCurrent() -> Bool {
        generation == requestGeneration && commandSequence == requestSequence && !isBusy
      }
      do {
        let result = try await gateway.motionCalibration(for: selector, command: nil)
        guard isCurrent() else { return }
        status = result
        errorMessage = nil
      } catch {
        guard isCurrent() else { return }
        status = nil
        errorMessage = Self.calibrationError(error)
      }
    }

    /// How long the status waits between reads while calibration is not settled.
    static let refreshIntervalNanoseconds: UInt64 = 1_000_000_000

    /// Returns whether the status can still change on the service side: before the motion baseline
    /// exists, and while samples are being collected.
    ///
    /// A failed read stops the loop; the user retries it.
    ///
    /// - Parameters:
    ///   - status: The latest status, or nil.
    ///   - errorMessage: The message of the latest failure, or nil.
    /// - Returns: Whether the status can still change on the service side: before the motion
    ///   baseline exists, and while samples are being collected.
    static func needsRefresh(
      status: RemappingMotionCalibrationStatus?,
      errorMessage: String?
    ) -> Bool {
      guard errorMessage == nil, let status else { return false }
      return !status.hasMotionBaseline || status.isCollecting
    }

    /// Reads the status, then keeps reading it every ``refreshIntervalNanoseconds`` while
    /// ``needsRefresh(status:errorMessage:)`` holds.
    ///
    /// Ends when the task is cancelled.
    ///
    /// - Parameter sleep: Waits between two reads.
    func refreshWhileCalibrating(
      sleep: @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) async {
      await refresh()
      while Self.needsRefresh(status: status, errorMessage: errorMessage) {
        do { try await sleep(Self.refreshIntervalNanoseconds) } catch { return }
        guard !Task.isCancelled else { return }
        await refresh()
      }
    }

    /// Sends `command` and shows the status it returns.
    ///
    /// One command runs at a time; a read in flight does not block it and its answer is dropped.
    ///
    /// - Parameter command: Start, pause or reset.
    func perform(_ command: RemappingMotionCalibrationCommand) async {
      guard let selector, !isBusy else { return }
      let requestGeneration = generation
      commandSequence &+= 1
      isBusy = true
      errorMessage = nil
      do {
        let result = try await gateway.motionCalibration(for: selector, command: command)
        guard generation == requestGeneration else { return }
        status = result
      } catch {
        guard generation == requestGeneration else { return }
        status = nil
        errorMessage = Self.calibrationError(error)
      }
      // A read that started while the command ran may predate its effect.
      commandSequence &+= 1
      isBusy = false
    }

    /// Returns the message for a failure.
    ///
    /// The service sends its refusals as remapping RPC errors; the gateway throws
    /// `controllerUnavailable` itself when the selector does not resolve.
    ///
    /// - Parameter error: The failure.
    /// - Returns: The message for a failure.
    private static func calibrationError(_ error: any Error) -> String {
      if let rejection = error as? ApplicationServiceRemappingRPCError {
        switch rejection.code {
        case .controllerUnavailable:
          return calibrationError(RemappingMotionCalibrationError.controllerUnavailable)
        case .motionUnavailable:
          return calibrationError(RemappingMotionCalibrationError.motionUnavailable)
        case .motionGyroNotSelected, .motionProfileInactive, .motionSessionChanged:
          return rejection.code.errorCode.localizedExplanation
        default: break
        }
      }
      switch error as? RemappingMotionCalibrationError {
      case .controllerUnavailable:
        return OJDLocalized.string(
          "ui.motion.calibration.controllerUnavailable"
        )
      case .motionUnavailable:
        return OJDLocalized.string(
          "ui.motion.calibration.motionUnavailable"
        )
      case nil: return RuntimePresentation.userFacingError(error)
      }
    }
  }
#endif
