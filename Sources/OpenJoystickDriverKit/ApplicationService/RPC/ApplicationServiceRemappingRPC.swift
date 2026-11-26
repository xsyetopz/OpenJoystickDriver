public import Foundation

/// Byte limits on the messages of the remapping RPC methods.
///
/// Decoded remapping arguments stay below the framed envelope limit of the local transport.
public enum ApplicationServiceRemappingRPC {
  /// The largest framed message of the local transport, in bytes.
  public static let maximumTransportFrameBytes = 8 * 1_024 * 1_024
  /// The largest encoded remapping data, in bytes.
  public static let maximumPayloadBytes = RemappingPayloadLimits.maximumEncodedBytes
  /// The largest encoded remapping argument, in bytes; equal to ``maximumPayloadBytes``.
  public static let maximumArgumentBytes = maximumPayloadBytes
}

/// The arguments of a request that names one remapping profile.
public struct ApplicationServiceRemappingProfileIDArguments: Codable, Sendable {
  /// The ID of the profile.
  public let profileID: UUID

  /// Creates the arguments for the profile `profileID`.
  public init(profileID: UUID) { self.profileID = profileID }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `profileID` key.
    case profileID
  }
}

/// The arguments that activate a remapping profile.
///
/// `allowEmpty` admits a profile that produces no output.
public struct ApplicationServiceRemappingActivateArguments: Codable, Sendable {
  /// The ID of the profile to activate.
  public let profileID: UUID
  /// Whether the service activates a profile that produces no output.
  public let allowEmpty: Bool

  /// Creates the arguments for the profile `profileID`.
  public init(profileID: UUID, allowEmpty: Bool) {
    self.profileID = profileID
    self.allowEmpty = allowEmpty
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `profileID` key.
    case profileID
    /// The `allowEmpty` key.
    case allowEmpty
  }
}

/// The arguments of a request that names a damaged profile or an unusable library by the ID of its
/// profile issue.
///
/// The ID comes from one specific library snapshot.
public struct ApplicationServiceRemappingProfileIssueArguments: Codable, Sendable {
  /// The ID of the profile issue.
  public let issueID: UUID

  /// Creates the arguments for the profile issue `issueID`.
  public init(issueID: UUID) { self.issueID = issueID }
}

/// A problem of the saved remapping profiles that the snapshot reports.
public struct ApplicationServiceRemappingProfileIssue: Codable, Equatable, Sendable, Identifiable {
  /// The kind of a profile issue.
  public enum Kind: String, Codable, Sendable {
    /// One profile file is damaged.
    case damagedProfile = "DamagedProfile"
    /// The profile library as a whole cannot be used.
    case unusableLibrary = "UnusableLibrary"
  }

  /// The ID of the issue; requests that repair the issue name it.
  public let id: UUID
  /// Whether one profile file or the whole library has the problem.
  public let kind: Kind
  /// Why the profile file or the selections could not be used.
  ///
  /// A profile file has ``ErrorCode/unsupportedAPIVersion`` for an unsupported `apiVersion`,
  /// ``ErrorCode/invalidProfile`` when it does not decode or validate, ``ErrorCode/duplicateName``
  /// when another profile has its name, and ``ErrorCode/corruptLibrary`` when its file name is not
  /// that of its ID. Unusable selections have ``ErrorCode/corruptLibrary``.
  public let code: ErrorCode
  /// A human-readable description of the problem.
  public let message: String
  /// The name of the stale `.json` file of an earlier alpha, or nil for any other issue.
  public let fileName: String?

  /// Creates a profile issue from its values.
  public init(
    id: UUID,
    kind: Kind = .damagedProfile,
    code: ErrorCode,
    message: String,
    fileName: String? = nil
  ) {
    self.id = id
    self.kind = kind
    self.code = code
    self.message = message
    self.fileName = fileName
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `id` key.
    case id
    /// The `kind` key.
    case kind
    /// The `code` key.
    case code
    /// The `message` key.
    case message
    /// The `fileName` key.
    case fileName
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decode(Kind.self, forKey: .kind)
    code = try container.decode(ErrorCode.self, forKey: .code)
    message = try container.decode(String.self, forKey: .message)
    fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
  }
}

/// The arguments of a request that carries one remapping profile.
///
/// Decoding fails with an ``ApplicationServiceRemappingRPCError`` when the profile is invalid or
/// has an unsupported `apiVersion`.
public struct ApplicationServiceRemappingProfileArguments: Codable, Sendable {
  /// The profile the request creates or imports.
  public let profile: RemappingProfile

  /// Creates the arguments for `profile`.
  public init(profile: RemappingProfile) { self.profile = profile }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `profile` key.
    case profile
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    profile = try container.decodeRequestProfile(forKey: .profile)
  }
}

/// Compare-and-swap arguments for an ordinary profile update.
///
/// Decoding fails with an ``ApplicationServiceRemappingRPCError`` when either profile is invalid or
/// has an unsupported `apiVersion`.
public struct ApplicationServiceRemappingProfileUpdateArguments: Codable, Sendable {
  /// The profile that replaces the stored one.
  public let profile: RemappingProfile
  /// The profile as the client last read it; the update fails when the stored profile differs.
  public let expectedCurrent: RemappingProfile

  /// Creates the arguments from the new profile and the expected stored one.
  public init(profile: RemappingProfile, expectedCurrent: RemappingProfile) {
    self.profile = profile
    self.expectedCurrent = expectedCurrent
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `profile` key.
    case profile
    /// The `expectedCurrent` key.
    case expectedCurrent
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    profile = try container.decodeRequestProfile(forKey: .profile)
    expectedCurrent = try container.decodeRequestProfile(forKey: .expectedCurrent)
  }
}

extension KeyedDecodingContainer {
  /// Decodes a profile of a remapping request.
  ///
  /// A profile with a missing or unsupported `apiVersion` fails with
  /// ``ApplicationServiceRemappingRPCError/Code/unsupportedAPIVersion``; any other profile that
  /// does not decode fails with ``ApplicationServiceRemappingRPCError/Code/invalidProfile``.
  func decodeRequestProfile(forKey key: Key) throws -> RemappingProfile {
    do { return try decode(RemappingProfile.self, forKey: key) } catch {
      if RemappingProfileFileStore.problemCode(error) == .unsupportedAPIVersion {
        throw ApplicationServiceRemappingRPCError(
          code: .unsupportedAPIVersion,
          message: "The remapping profile has a missing or unsupported apiVersion."
        )
      }
      throw ApplicationServiceRemappingRPCError(
        code: .invalidProfile,
        message: "The remapping profile is not valid."
      )
    }
  }
}

/// The arguments of a request that names a controller model by its vendor and product IDs.
public struct ApplicationServiceRemappingModelArguments: Codable, Sendable {
  /// The USB vendor ID of the controller model.
  public let vendorID: UInt16
  /// The USB product ID of the controller model.
  public let productID: UInt16

  /// Creates the arguments for the model `vendorID`:`productID`.
  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `vendorID` key.
    case vendorID
    /// The `productID` key.
    case productID
  }
}
