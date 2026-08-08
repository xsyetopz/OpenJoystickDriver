import Foundation

/// Stable application-service method names for controller remapping operations.
public enum ApplicationServiceRemappingRPCMethod: String, CaseIterable, Sendable {
  case getSnapshot = "getRemappingSnapshot"
  case getProfile = "getRemappingProfile"
  case createProfile = "createRemappingProfile"
  case updateProfile = "updateRemappingProfile"
  case deleteProfile = "deleteRemappingProfile"
  case importProfile = "importRemappingProfile"
  case activateProfile = "activateRemappingProfile"
  case deactivateProfile = "deactivateRemappingProfile"
  case deactivateProfileByID = "deactivateRemappingProfileByID"
  case getPostEventAccess = "getRemappingPostEventAccess"
  case requestPostEventAccess = "requestRemappingPostEventAccess"
}

/// Bounds decoded remapping arguments below the local transport's framed envelope limit.
public enum ApplicationServiceRemappingRPC {
  public static let maximumTransportFrameBytes = 8 * 1_024 * 1_024
  public static let maximumPayloadBytes = RemappingPayloadLimits.maximumEncodedBytes
  public static let maximumArgumentBytes = maximumPayloadBytes
}

public struct ApplicationServiceRemappingProfileIDArguments: Codable, Sendable {
  public let profileID: UUID

  public init(profileID: UUID) { self.profileID = profileID }

  private enum CodingKeys: String, CodingKey { case profileID = "profile_id" }
}

public struct ApplicationServiceRemappingProfileArguments: Codable, Sendable {
  public let profile: RemappingProfile

  public init(profile: RemappingProfile) { self.profile = profile }
}

/// Compare-and-swap arguments for an ordinary profile update.
public struct ApplicationServiceRemappingProfileUpdateArguments: Codable, Sendable {
  public let profile: RemappingProfile
  public let expectedCurrent: RemappingProfile

  public init(profile: RemappingProfile, expectedCurrent: RemappingProfile) {
    self.profile = profile
    self.expectedCurrent = expectedCurrent
  }

  private enum CodingKeys: String, CodingKey {
    case profile
    case expectedCurrent = "expected_current"
  }
}

public struct ApplicationServiceRemappingModelArguments: Codable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16

  public init(vendorID: UInt16, productID: UInt16) {
    self.vendorID = vendorID
    self.productID = productID
  }

  private enum CodingKeys: String, CodingKey {
    case vendorID = "vendor_id"
    case productID = "product_id"
  }
}

public struct ApplicationServiceRemappingActiveProfilePayload: Codable, Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let profileID: UUID
  public let profileName: String
  public let applicationScope: RemappingApplicationScope

  public init(
    vendorID: UInt16,
    productID: UInt16,
    profileID: UUID,
    profileName: String,
    applicationScope: RemappingApplicationScope
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.profileID = profileID
    self.profileName = profileName
    self.applicationScope = applicationScope
  }

  private enum CodingKeys: String, CodingKey {
    case vendorID = "vendor_id"
    case productID = "product_id"
    case profileID = "profile_id"
    case profileName = "profile_name"
    case applicationScope = "application_scope"
  }
}

public enum ApplicationServiceRemappingRouteSelection: String, Codable, Sendable {
  case compatibility
  case remapping
  case unavailable
}

public enum ApplicationServiceRemappingRouteEligibility: String, Codable, Sendable {
  case compatibilityOutputSuppressed = "compatibility_output_suppressed"
  case eligible
  case outputSuppressed = "output_suppressed"
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  case unavailable
}

public struct ApplicationServiceRemappingFailurePayload: Codable, Equatable, Sendable {
  public let code: ApplicationServiceRemappingRPCError.Code
  public let message: String

  public init(code: ApplicationServiceRemappingRPCError.Code, message: String) {
    self.code = code
    self.message = message
  }
}

public struct ApplicationServiceRemappingRoutePayload: Codable, Equatable, Sendable {
  public let vendorID: UInt16
  public let productID: UInt16
  public let runtimeIdentifier: String
  public let selection: ApplicationServiceRemappingRouteSelection
  public let eligibility: ApplicationServiceRemappingRouteEligibility
  public let activeProfileID: UUID?
  public let activeProfileName: String?
  public let applicationScope: RemappingApplicationScope?
  public let frontmostBundleIdentifier: String?
  public let postEventAccess: RemappingPostEventAccessState
  public let failure: ApplicationServiceRemappingFailurePayload?

  public init(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String,
    selection: ApplicationServiceRemappingRouteSelection,
    eligibility: ApplicationServiceRemappingRouteEligibility,
    activeProfileID: UUID?,
    activeProfileName: String?,
    applicationScope: RemappingApplicationScope?,
    frontmostBundleIdentifier: String?,
    postEventAccess: RemappingPostEventAccessState,
    failure: ApplicationServiceRemappingFailurePayload?
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.runtimeIdentifier = runtimeIdentifier
    self.selection = selection
    self.eligibility = eligibility
    self.activeProfileID = activeProfileID
    self.activeProfileName = activeProfileName
    self.applicationScope = applicationScope
    self.frontmostBundleIdentifier = frontmostBundleIdentifier
    self.postEventAccess = postEventAccess
    self.failure = failure
  }

  private enum CodingKeys: String, CodingKey {
    case vendorID = "vendor_id"
    case productID = "product_id"
    case runtimeIdentifier = "runtime_identifier"
    case selection
    case eligibility
    case activeProfileID = "active_profile_id"
    case activeProfileName = "active_profile_name"
    case applicationScope = "application_scope"
    case frontmostBundleIdentifier = "frontmost_bundle_id"
    case postEventAccess = "post_event_access"
    case failure
  }
}

public struct ApplicationServiceRemappingSnapshotPayload: Codable, Equatable, Sendable {
  public let profiles: [RemappingProfile]
  public let activeProfiles: [ApplicationServiceRemappingActiveProfilePayload]
  public let routes: [ApplicationServiceRemappingRoutePayload]
  public let postEventAccess: RemappingPostEventAccessState

  public init(
    profiles: [RemappingProfile],
    activeProfiles: [ApplicationServiceRemappingActiveProfilePayload],
    routes: [ApplicationServiceRemappingRoutePayload],
    postEventAccess: RemappingPostEventAccessState
  ) {
    self.profiles = profiles
    self.activeProfiles = activeProfiles
    self.routes = routes
    self.postEventAccess = postEventAccess
  }

  private enum CodingKeys: String, CodingKey {
    case profiles
    case activeProfiles = "active_profiles"
    case routes
    case postEventAccess = "post_event_access"
  }
}

/// A deterministic, code-bearing remapping failure transported in the existing RPC error string.
public struct ApplicationServiceRemappingRPCError: Error, Codable, Equatable, LocalizedError,
  Sendable
{
  public enum Code: String, Codable, Sendable {
    case argumentTooLarge = "argument_too_large"
    case corruptLibrary = "library_corrupt"
    case duplicateName = "duplicate_name"
    case invalidArguments = "invalid_arguments"
    case invalidProfile = "invalid_profile"
    case librarySizeExceeded = "library_size_exceeded"
    case profileAlreadyExists = "profile_already_exists"
    case profileUpdateConflict = "profile_update_conflict"
    case profileCountExceeded = "profile_count_exceeded"
    case profileNotFound = "profile_not_found"
    case responseEncodingFailed = "response_encoding_failed"
    case responseTooLarge = "response_too_large"
    case routerEngineUnavailable = "router_engine_unavailable"
    case routerLibraryAndEngineUnavailable = "router_library_and_engine_unavailable"
    case routerLibraryUnavailable = "router_library_unavailable"
    case routerShutDown = "router_shut_down"
    case transactionUnreconciled = "transaction_unreconciled"
    case unreadableLibrary = "library_unreadable"
    case unsupportedLibraryVersion = "unsupported_library_version"
    case unwritableLibrary = "library_unwritable"
    case unexpected = "unexpected"
  }

  public let code: Code
  public let message: String

  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }

  public var errorDescription: String? { message }

  public var rpcDescription: String {
    guard let data = try? JSONEncoder().encode(self) else { return message }
    return "OJD_REMAPPING_ERROR:" + data.base64EncodedString()
  }

  public init?(rpcDescription: String) {
    let prefix = "OJD_REMAPPING_ERROR:"
    guard rpcDescription.hasPrefix(prefix),
      let data = Data(base64Encoded: String(rpcDescription.dropFirst(prefix.count))),
      let decoded = try? JSONDecoder().decode(Self.self, from: data)
    else { return nil }
    self = decoded
  }
}
