import Foundation
import OpenJoystickDriverKit

extension RemappingRequestCoordinator {

  static func rpcError(_ error: any Error) -> ApplicationServiceRemappingRPCError {
    if let error = error as? ApplicationServiceRemappingRPCError { return error }
    if let error = error as? RemappingProfileLibraryError { return libraryError(error) }
    if let error = error as? RemappingOutputRoutingError { return routingError(error) }
    if let error = error as? RemappingMotionCalibrationError {
      return ApplicationServiceRemappingRPCError(
        code: error == .controllerUnavailable ? .controllerUnavailable : .motionUnavailable,
        message: error == .controllerUnavailable
          ? "The selected controller is unavailable."
          : "Motion calibration requires an eligible controller with motion samples."
      )
    }
    if let error = error as? RemappingMotionCalibrationRefusal {
      switch error {
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
    if let error = error as? RemappingJoyConPairError {
      return ApplicationServiceRemappingRPCError(
        code: .joyConPairUnavailable,
        message: error.localizedDescription
      )
    }
    if let error = error as? RemappingEventEngineError {
      return ApplicationServiceRemappingRPCError(
        code: .routerEngineUnavailable,
        message: error.localizedDescription
      )
    }
    return ApplicationServiceRemappingRPCError(
      code: .unexpected,
      message: error.localizedDescription
    )
  }

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
    }
    return ApplicationServiceRemappingRPCError(code: code, message: error.localizedDescription)
  }

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
