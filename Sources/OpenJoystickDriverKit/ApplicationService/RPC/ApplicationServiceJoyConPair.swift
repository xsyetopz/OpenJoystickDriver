public import Foundation

/// The arguments that pair two Joy-Con into one remapped controller.
public struct ApplicationServiceJoyConPairArguments: Codable, Sendable {
  /// The left Joy-Con.
  public let left: ControllerReference
  /// The right Joy-Con.
  public let right: ControllerReference
  /// The ID of the profile that remaps the pair.
  public let profileID: UUID

  /// Creates the arguments for the pair of `left` and `right` under the profile `profileID`.
  public init(left: ControllerReference, right: ControllerReference, profileID: UUID) {
    self.left = left
    self.right = right
    self.profileID = profileID
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `left` key.
    case left
    /// The `right` key.
    case right
    /// The `profileID` key.
    case profileID
  }
}

/// The arguments that end a Joy-Con pair, named by the pair's session ID.
public struct ApplicationServiceJoyConUnpairArguments: Codable, Sendable {
  /// The session ID of the pair.
  public let sessionID: UUID

  /// Creates the arguments for the pair session `sessionID`.
  public init(sessionID: UUID) { self.sessionID = sessionID }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `sessionID` key.
    case sessionID
  }
}

/// A Joy-Con pair that the remapping snapshot lists.
public struct ApplicationServiceJoyConPairPayload: Codable, Equatable, Sendable {
  /// The session ID of the pair.
  public let sessionID: UUID
  /// The session token of the left Joy-Con.
  public let left: ControllerSessionToken
  /// The session token of the right Joy-Con.
  public let right: ControllerSessionToken
  /// The ID of the profile that remaps the pair.
  public let profileID: UUID
  /// The name of the profile that remaps the pair.
  public let profileName: String
  /// The Joy-Con whose gyro the pair's profile uses.
  public let gyroSelection: RemappingJoyConGyroSelection

  /// Creates a pair data from its values.
  public init(
    sessionID: UUID,
    left: ControllerSessionToken,
    right: ControllerSessionToken,
    profileID: UUID,
    profileName: String,
    gyroSelection: RemappingJoyConGyroSelection
  ) {
    self.sessionID = sessionID
    self.left = left
    self.right = right
    self.profileID = profileID
    self.profileName = profileName
    self.gyroSelection = gyroSelection
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `sessionID` key.
    case sessionID
    /// The `left` key.
    case left
    /// The `right` key.
    case right
    /// The `profileID` key.
    case profileID
    /// The `profileName` key.
    case profileName
    /// The `gyroSelection` key.
    case gyroSelection
  }
}
