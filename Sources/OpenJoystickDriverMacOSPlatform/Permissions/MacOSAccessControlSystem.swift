import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import OpenJoystickDriverKit

/// Reads and requests the macOS HID permissions through the IOHID access calls.
package struct MacOSAccessControlSystem: AccessControlSystem {
  /// Creates the access control system.
  package init() {}

  /// Reads the state of the permission to listen to input events.
  package func inputReadAccessState() -> PermissionManager.AccessState {
    Self.accessState(for: kIOHIDRequestTypeListenEvent)
  }

  /// IOHIDUserDevice creation is authorized through the post-event TCC service.
  package func inputInjectAccessState() -> PermissionManager.AccessState {
    Self.accessState(for: kIOHIDRequestTypePostEvent)
  }

  /// Reads whether the process may post events.
  package func postEventAccessState() -> RemappingPostEventAccessState {
    CGPreflightPostEventAccess() ? .granted : .notAuthorized
  }

  /// Asks macOS for the permission to listen to input events.
  @MainActor
  package func requestInputReadAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

  /// Asks macOS for the permission to post events.
  @MainActor
  package func requestInputInjectAccess() { _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent) }

  /// Maps the IOHID access answer for `requestType` to a permission state.
  private static func accessState(
    for requestType: IOHIDRequestType
  )
    -> PermissionManager.AccessState
  {
    switch IOHIDCheckAccess(requestType) {
    case kIOHIDAccessTypeGranted: return .granted
    case kIOHIDAccessTypeDenied: return .denied
    default: return .unknown
    }
  }
}
