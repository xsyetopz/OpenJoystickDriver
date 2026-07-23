import OpenJoystickDriverKit

enum StatusPermissionState: String, Sendable, Equatable {
  case granted
  case denied
  case unknown
  case unavailable

  init(_ state: PermissionManager.AccessState) {
    switch state {
    case .granted: self = .granted
    case .denied: self = .denied
    case .unknown: self = .unknown
    }
  }

  var accessState: PermissionManager.AccessState? {
    switch self {
    case .granted: return .granted
    case .denied: return .denied
    case .unknown: return .unknown
    case .unavailable: return nil
    }
  }
}
