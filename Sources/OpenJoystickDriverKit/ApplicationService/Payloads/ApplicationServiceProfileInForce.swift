/// The remapping profile in force for one controller, reported in
/// ``ApplicationServiceDeviceDescription``.
public struct ApplicationServiceProfileInForce: Codable, Equatable, Sendable {
  /// The name of the profile.
  public let name: String
  /// The bundle identifier of the app in front that selected the profile; nil when the profile
  /// does not depend on the app in front.
  public let appID: String?

  /// Creates the value.
  public init(name: String, appID: String?) {
    self.name = name
    self.appID = appID
  }
}
