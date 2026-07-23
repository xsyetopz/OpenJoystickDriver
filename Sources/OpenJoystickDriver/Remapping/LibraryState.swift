import Foundation
import OpenJoystickDriverKit

struct RemappingProfileLibrarySnapshot: Sendable {
  let profiles: [RemappingProfile]
  let activeProfiles: [RemappingActiveProfileSelection]
}

struct RemappingActiveProfileSelection: Sendable {
  let model: RemappingProfileModel
  let profileID: UUID
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
  static let currentSchemaVersion = 1

  var schemaVersion = Self.currentSchemaVersion
  var profiles: [RemappingProfile] = []
  var activeProfiles: [RemappingPersistedActiveProfile] = []

  private enum CodingKeys: String, CodingKey {
    case schemaVersion = "schema_version"
    case profiles
    case activeProfiles = "active_profiles"
  }
}

struct RemappingPersistedActiveProfile: Codable, Sendable {
  let model: RemappingProfileModel
  let profileID: UUID

  private enum CodingKeys: String, CodingKey {
    case model
    case profileID = "profile_id"
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
