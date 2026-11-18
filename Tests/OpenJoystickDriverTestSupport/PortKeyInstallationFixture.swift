public import CryptoKit
import Foundation
public import OpenJoystickDriverKit

/// The installation key that tests pass wherever the service computes port keys, so a test never
/// reads or creates the user's `PortKeyInstallation.key`.
public let testPortKeyInstallationKey = SymmetricKey(data: Data(repeating: 7, count: 32))

extension LogicalControllerID {
  /// The port key of this controller under ``testPortKeyInstallationKey``; nil without a location
  /// ID.
  public var testPortKey: ControllerPortKey? {
    ControllerPortKey.of(self, installationKey: testPortKeyInstallationKey)
  }
}
