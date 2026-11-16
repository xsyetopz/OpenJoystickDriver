import Foundation
import OpenJoystickDriverKit

extension RemappingRequestCoordinator {

  /// Maps `error` to the RPC error that carries its code and message to the client.
  static func rpcError(_ error: any Error) -> ApplicationServiceRemappingRPCError {
    if let existing = error as? ApplicationServiceRemappingRPCError { return existing }
    if let failure = error as? RemappingProfileLibraryError { return libraryError(failure) }
    if let failure = error as? RemappingOutputRoutingError { return routingError(failure) }
    if let calibration = error as? RemappingMotionCalibrationError {
      return ApplicationServiceRemappingRPCError(
        code: calibration == .controllerUnavailable ? .controllerUnavailable : .motionUnavailable,
        message: calibration == .controllerUnavailable
          ? "The selected controller is unavailable."
          : "Motion calibration requires an eligible controller with motion samples."
      )
    }
    if let refusal = error as? RemappingMotionCalibrationRefusal {
      switch refusal {
      case .gyroNotSelected:
        return ApplicationServiceRemappingRPCError(
          code: .motionGyroNotSelected,
          message: "The Joy-Con pair profile takes its gyro from another controller."
        )
      case .profileInactive:
        return ApplicationServiceRemappingRPCError(
          code: .motionProfileInactive,
          message: "Motion calibration requires an active remapping profile for the controller."
        )
      case .sessionChanged:
        return ApplicationServiceRemappingRPCError(
          code: .motionSessionChanged,
          message: "The controller's remapping session changed during the request."
        )
      }
    }
    if let pair = error as? RemappingJoyConPairError {
      return ApplicationServiceRemappingRPCError(
        code: .joyConPairUnavailable,
        message: pair.localizedDescription
      )
    }
    if let engine = error as? RemappingEventEngineError {
      return ApplicationServiceRemappingRPCError(
        code: .routerEngineUnavailable,
        message: engine.localizedDescription
      )
    }
    return ApplicationServiceRemappingRPCError(
      code: .unexpected,
      message: error.localizedDescription
    )
  }

  /// Returns the error for a mutation that failed and could not be reconciled, naming the original
  /// failure and `detail`.
  static func unreconciledError(
    original: ApplicationServiceRemappingRPCError,
    detail: String
  ) -> ApplicationServiceRemappingRPCError {
    ApplicationServiceRemappingRPCError(
      code: .transactionUnreconciled,
      message: "Remapping mutation failed [\(original.code.rawValue)]: "
        + "\(original.message) \(detail)"
    )
  }

  /// Maps a profile library error to its RPC error code.
  private static func libraryError(
    _ error: RemappingProfileLibraryError
  ) -> ApplicationServiceRemappingRPCError {
    let code: ApplicationServiceRemappingRPCError.Code
    switch error {
    case .corruptLibrary: code = .corruptLibrary
    case .duplicateName: code = .duplicateName
    case .invalidProfile: code = .invalidProfile
    case .profileCountExceeded: code = .profileCountExceeded
    case .profileAlreadyExists: code = .profileAlreadyExists
    case .profileNotFound: code = .profileNotFound
    case .pairProfileRequiresExplicitSession: code = .invalidArguments
    case .profileProducesNoOutput: code = .profileProducesNoOutput
    case .profileUpdateConflict: code = .profileUpdateConflict
    case .unreadableLibrary: code = .unreadableLibrary
    case .unwritableLibrary: code = .unwritableLibrary
    case .profileRecoveryRequired, .profileIssueNotFound: code = .profileRecoveryRequired
    case .packageProfileReadOnly: code = .packageProfileReadOnly
    }
    return ApplicationServiceRemappingRPCError(code: code, message: error.localizedDescription)
  }

  /// Maps a routing error to its RPC error code.
  private static func routingError(
    _ error: RemappingOutputRoutingError
  ) -> ApplicationServiceRemappingRPCError {
    let code: ApplicationServiceRemappingRPCError.Code
    switch error {
    case .engine: code = .routerEngineUnavailable
    case .library: code = .routerLibraryUnavailable
    case .libraryAndEngine: code = .routerLibraryAndEngineUnavailable
    case .profileTransactionAlreadyActive, .profileTransactionUnreconciled,
      .profileTransactionViolation:
      code = .transactionUnreconciled
    case .shutDown: code = .routerShutDown
    }
    return ApplicationServiceRemappingRPCError(code: code, message: error.localizedDescription)
  }
}
