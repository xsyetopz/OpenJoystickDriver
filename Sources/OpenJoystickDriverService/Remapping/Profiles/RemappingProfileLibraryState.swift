import Foundation
import OpenJoystickDriverKit

struct RemappingProfileLibrarySnapshot: Sendable {
  let profiles: [RemappingProfile]
  let activeProfiles: [RemappingActiveProfileSelection]
  let issues: [ApplicationServiceRemappingProfileIssue]
}

struct RemappingActiveProfileSelection: Sendable {
  let model: RemappingProfileModel
  let profileID: UUID
  let applicationScope: RemappingApplicationScope?
}

struct RemappingProfileMutationImpact: Sendable {
  let modelsNeedingRefresh: Set<RemappingProfileModel>
}

struct RemappingProfileLibraryCheckpoint: Sendable {
  struct File: Sendable {
    let data: Data
    let permissions: Int?
  }

  let cachedLibrary: RemappingProfileLibraryState?
  let cachedIssues: [UUID: RemappingProfileLibrary.RecoveryIssue]
  let rootPermissions: Int?
  let profilesDirectoryPermissions: Int?
  /// Keyed by file name in `Profiles/`.
  let profileFiles: [String: File]
  let selections: File?
}

struct RemappingProfileLibraryState: Equatable, Sendable {
  var profiles: [RemappingProfile] = []
  var activeProfiles: [RemappingPersistedActiveProfile] = []
}

struct RemappingPersistedActiveProfile: Codable, Equatable, Sendable {
  let model: RemappingProfileModel
  let profileID: UUID
  let applicationScope: RemappingApplicationScope?

  init(
    model: RemappingProfileModel,
    profileID: UUID,
    applicationScope: RemappingApplicationScope? = nil
  ) {
    self.model = model
    self.profileID = profileID
    self.applicationScope = applicationScope
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case model
    case profileID
    case applicationScope
  }

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

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(model, forKey: .model)
    try container.encode(profileID, forKey: .profileID)
    try container.encodeIfPresent(applicationScope, forKey: .applicationScope)
  }
}

struct RemappingProfileModel: Codable, Equatable, Hashable, Sendable {
  let vendorID: UInt16
  let productID: UInt16

  init(_ device: RemappingDeviceScope) {
    self.init(vendorID: device.vendorID, productID: device.productID)
  }

  init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  private enum CodingKeys: String, CodingKey, CaseIterable {
    case vendorID
    case productID
  }

  init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let values = try decoder.container(keyedBy: CodingKeys.self)
    vendorID = try values.decode(UInt16.self, forKey: .vendorID)
    productID = try values.decode(UInt16.self, forKey: .productID)
  }
}
