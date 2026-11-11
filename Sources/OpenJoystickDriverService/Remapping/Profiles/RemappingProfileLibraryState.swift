import Foundation
import OpenJoystickDriverKit

/// The profiles and the active selections of the library, with the issues of its files.
struct RemappingProfileLibrarySnapshot: Sendable {
  /// Every profile, local and from packages.
  let profiles: [RemappingProfile]
  /// The active selection of every model.
  let activeProfiles: [RemappingActiveProfileSelection]
  /// The damaged files that need recovery.
  let issues: [ApplicationServiceRemappingProfileIssue]
}

/// The active profile of one controller model and application scope.
struct RemappingActiveProfileSelection: Sendable {
  /// The controller model.
  let model: RemappingProfileModel
  /// The ID of the active profile.
  let profileID: UUID
  /// The applications the selection applies to, or nil for every application.
  let applicationScope: RemappingApplicationScope?
}

/// The models whose active profile a change affects.
struct RemappingProfileMutationImpact: Sendable {
  /// The models that need their selection refreshed.
  let modelsNeedingRefresh: Set<RemappingProfileModel>
}

/// The files and permissions of the library, so the library can be restored to this state.
struct RemappingProfileLibraryCheckpoint: Sendable {
  /// One file of the library.
  struct File: Sendable {
    /// The bytes of the file.
    let data: Data
    /// The POSIX permissions of the file, when it exists.
    let permissions: Int?
  }

  /// The library in memory, when it was loaded.
  let cachedLibrary: RemappingProfileLibraryState?
  /// The issues that were reported.
  let cachedIssues: [UUID: RemappingProfileLibrary.RecoveryIssue]
  /// The permissions of the library directory, when it exists.
  let rootPermissions: Int?
  /// The permissions of the `Profiles/` directory, when it exists.
  let profilesDirectoryPermissions: Int?
  /// Keyed by file name in `Profiles/`.
  let profileFiles: [String: File]
  /// The selections file, when it exists.
  let selections: File?
}

/// The persisted state of the library: the local profiles and the active selections.
struct RemappingProfileLibraryState: Equatable, Sendable {
  /// The local profiles.
  var profiles: [RemappingProfile] = []
  /// The active selections.
  var activeProfiles: [RemappingPersistedActiveProfile] = []
}

/// The persisted active profile of one model and application scope.
struct RemappingPersistedActiveProfile: Codable, Equatable, Sendable {
  /// The controller model.
  let model: RemappingProfileModel
  /// The ID of the active profile.
  let profileID: UUID
  /// The applications the selection applies to, or nil for every application.
  let applicationScope: RemappingApplicationScope?

  /// Creates the selection.
  init(
    model: RemappingProfileModel,
    profileID: UUID,
    applicationScope: RemappingApplicationScope? = nil
  ) {
    self.model = model
    self.profileID = profileID
    self.applicationScope = applicationScope
  }

  /// The keys of the persisted selection.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The key of the model.
    case model
    /// The key of the profile ID.
    case profileID
    /// The key of the application scope.
    case applicationScope
  }

  /// Decodes the selection and rejects unknown keys.
  init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    model = try container.decode(RemappingProfileModel.self, forKey: .model)
    profileID = try container.decode(UUID.self, forKey: .profileID)
    applicationScope = try container.decodeIfPresent(
      RemappingApplicationScope.self,
      forKey: .applicationScope
    )
  }

  /// Encodes the selection.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(model, forKey: .model)
    try container.encode(profileID, forKey: .profileID)
    try container.encodeIfPresent(applicationScope, forKey: .applicationScope)
  }
}

/// The vendor and product ID of a controller model that a profile is for.
struct RemappingProfileModel: Codable, Equatable, Hashable, Sendable {
  /// The USB vendor ID.
  let vendorID: UInt16
  /// The USB product ID.
  let productID: UInt16

  /// Creates the model of `device`.
  init(_ device: RemappingDeviceScope) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }

  /// Creates the model of the given vendor and product IDs.
  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  /// The keys of the persisted model.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The key of the vendor ID.
    case vendorID
    /// The key of the product ID.
    case productID
  }

  /// Decodes the model and rejects unknown keys.
  init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try values.decode(UInt16.self, forKey: .vendorID)
    productID = try values.decode(UInt16.self, forKey: .productID)
  }
}
