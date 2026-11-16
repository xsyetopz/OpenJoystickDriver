import Foundation
public import OpenJoystickDriverKit

extension RootedDataDirectory {
  /// A fresh data directory under the temp location of the port, so a test never touches the
  /// user's real stores.
  public static func temporary() -> RootedDataDirectory {
    RootedDataDirectory(
      root: MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
        "OpenJoystickDriverTests-\(UUID().uuidString)",
        isDirectory: true
      )
    )
  }
}
