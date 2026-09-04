import Foundation
import OpenJoystickDriverKit

struct RemappingProfileLibrarySnapshot: Sendable {
  let profiles: [RemappingProfile]
  let activeProfiles: [RemappingActiveProfileSelection]
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
  let cachedLibrary: RemappingProfileLibraryState?
  let persistedData: Data?
  let parentExisted: Bool
  let parentPermissions: Int?
  let filePermissions: Int?
}

struct RemappingProfileLibraryState: Codable, Sendable {
  static let currentSchemaVersion = 2

  var schemaVersion = Self.currentSchemaVersion
  var profiles: [RemappingProfile] = []
  var activeProfiles: [RemappingPersistedActiveProfile] = []

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profiles
    case activeProfiles = "active_profiles"
  }

  init() {}

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    profiles = try container.decode([RemappingProfile].self, forKey: .profiles)
    activeProfiles =
      try container.decodeIfPresent([RemappingPersistedActiveProfile].self, forKey: .activeProfiles)
      ?? []
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(schemaVersion, forKey: .schemaVersion)
    try container.encode(profiles, forKey: .profiles)
    try container.encode(activeProfiles, forKey: .activeProfiles)
  }
}

struct RemappingPersistedActiveProfile: Codable, Sendable {
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

  private enum CodingKeys: String, CodingKey {
    case model
    case profileID = "profile_id"
    case applicationScope = "application_scope"
  }

  init(from decoder: any Decoder) throws {
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

  private enum CodingKeys: String, CodingKey {
    case vendorID = "vendor_id"
    case productID = "product_id"
  }
}
