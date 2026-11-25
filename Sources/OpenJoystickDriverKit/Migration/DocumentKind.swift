/// A document that an upgrade cannot convert mechanically.
public struct DocumentMigrationProblem: Error, Equatable, CustomStringConvertible, Sendable {
  /// What has no mechanical mapping, naming the field.
  public let description: String

  /// Creates the problem from its text.
  init(_ description: String) { self.description = description }
}

/// The kinds of stored document that an upgrade converts.
enum DocumentKind: String, CaseIterable, Sendable {
  /// `Settings.plist`.
  case settings = "Settings"
  /// `AccessGrants.plist`.
  case accessGrants = "AccessGrants"
  /// A profile in `Profiles/`.
  case profile = "Profile"
  /// A user controller record in `Controllers/`.
  case controller = "Controller"
  /// A user controller patch in `Controllers/`.
  case controllerPatch = "ControllerPatch"
  /// The `mod` file of a package.
  case modPackage = "ModPackage"
  /// A virtual device file in `VirtualDevices/`.
  case virtualDevice = "VirtualDevice"
}
