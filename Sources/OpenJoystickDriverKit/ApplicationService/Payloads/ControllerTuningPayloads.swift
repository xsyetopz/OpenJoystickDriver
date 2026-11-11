import Foundation

/// Arguments of `setControllerTuning`: the controller model, a tuning key, and its value in the
/// user's record; a nil `value` removes the key from the user's record.
public struct LocalServiceRPCControllerTuningArguments: Codable, Sendable {
  /// The USB vendor ID of the controller model.
  public let vendorID: Int
  /// The USB product ID of the controller model.
  public let productID: Int
  /// The tuning key.
  public let key: ControllerTuning.Key
  /// The value to store; nil removes the key.
  public let value: Double?

  /// Creates the arguments from a model, a key and a value.
  public init(vendorID: Int, productID: Int, key: ControllerTuning.Key, value: Double?) {
    self.vendorID = vendorID
    self.productID = productID
    self.key = key
    self.value = value
  }
}

/// Why a `setControllerTuning` request changed nothing.
///
/// The user record is unchanged.
public enum ControllerTuningFailure: String, Codable, Equatable, Sendable {
  /// Neither the user directory, the bundled catalog, nor an installed package has a record of
  /// the model, so there is nothing to patch.
  case noRecord
  /// The existing user record, or the record with the value set, is invalid, such as a
  /// `stickDeadzone` out of range.
  case invalidRecord
  /// The user record does not set the key, so there is nothing to remove.
  case notSet
  /// The user record cannot be written.
  case persistenceFailed
  /// The request names a vendor or product ID that does not fit 16 bits, so it names no model.
  case invalidRequest
}

/// Result of `setControllerTuning`.
public struct ControllerTuningResult: Codable, Equatable, Sendable {
  /// The tuning key the request named.
  public let key: ControllerTuning.Key
  /// The value the request asked for; nil when it asked to remove the key.
  public let value: Double?
  /// The model's effective value of the key before the request; nil when no layer set it.
  public let previous: Double?
  /// The user record the request writes; nil when it was refused before a file was chosen.
  public let file: String?
  /// Whether the request created the user record.
  public let created: Bool
  /// Why the request changed nothing; nil when it succeeded.
  public let failure: ControllerTuningFailure?
  /// The problem text of `invalidRecord` or `persistenceFailed`.
  public let detail: String?

  /// Creates the result from its values.
  public init(
    key: ControllerTuning.Key,
    value: Double?,
    previous: Double?,
    file: String?,
    created: Bool,
    failure: ControllerTuningFailure?,
    detail: String? = nil
  ) {
    self.key = key
    self.value = value
    self.previous = previous
    self.file = file
    self.created = created
    self.failure = failure
    self.detail = detail
  }
}
