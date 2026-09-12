#if canImport(SwiftUI)
  import Foundation
  import SwiftUI
  import OpenJoystickDriverKit

  protocol MotionCalibrationGateway: Sendable {
    func motionCalibration(
      for selector: RuntimeDeviceSelector,
      command: RemappingMotionCalibrationCommand?
    ) async throws -> RemappingMotionCalibrationStatus
  }

  @MainActor final class MotionCalibrationViewModel: ObservableObject {
    @Published private(set) var status: RemappingMotionCalibrationStatus?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isBusy = false
    @Published private(set) var selector: RuntimeDeviceSelector?
    private let gateway: any MotionCalibrationGateway
    private var generation: UInt64 = 0

    init(gateway: any MotionCalibrationGateway) { self.gateway = gateway }

    func select(_ selector: RuntimeDeviceSelector?) {
      guard self.selector != selector else { return }
      generation &+= 1
      self.selector = selector
      status = nil
      errorMessage = nil
      isBusy = false
    }

    func refresh() async { await perform(nil) }

    func perform(_ command: RemappingMotionCalibrationCommand?) async {
      guard let selector, !isBusy else { return }
      let requestGeneration = generation
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
      isBusy = false
    }

    private static func calibrationError(_ error: any Error) -> String {
      switch error as? RemappingMotionCalibrationError {
      case .controllerUnavailable:
        return OJDLocalized.string(
          "motion.calibration.controllerUnavailable",
          fallback: "Reconnect the controller, then refresh calibration status."
        )
      case .motionUnavailable:
        return OJDLocalized.string(
          "motion.calibration.motionUnavailable",
          fallback: "Enable a remapping profile for this controller "
          + "and check that motion is available."
        )
      case nil: return RuntimePresentation.userFacingError(error)
      }
    }
  }
#endif
