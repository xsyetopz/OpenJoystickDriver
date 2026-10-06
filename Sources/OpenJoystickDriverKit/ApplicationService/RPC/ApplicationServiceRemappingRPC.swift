import Foundation

/// Bounds decoded remapping arguments below the local transport's framed envelope limit.
public enum ApplicationServiceRemappingRPC {
  public static let maximumTransportFrameBytes = 8 * 1_024 * 1_024
  public static let maximumPayloadBytes = RemappingPayloadLimits.maximumEncodedBytes
  public static let maximumArgumentBytes = maximumPayloadBytes
}

public struct ApplicationServiceRemappingProfileIDArguments: Codable, Sendable {
  public let profileID: UUID

  public init(profileID: UUID) { self.profileID = profileID }

  private enum CodingKeys: String, CodingKey { case profileID }
}

/// Activates a profile; `allowEmpty` admits a profile that produces no output.
public struct ApplicationServiceRemappingActivateArguments: Codable, Sendable {
  public let profileID: UUID
  public let allowEmpty: Bool

  public init(profileID: UUID, allowEmpty: Bool) {
    self.profileID = profileID
    self.allowEmpty = allowEmpty
  }

  private enum CodingKeys: String, CodingKey { case profileID, allowEmpty }
}

/// Identifies a damaged persisted profile from one specific library snapshot.
public struct ApplicationServiceRemappingProfileIssueArguments: Codable, Sendable {
  public let issueID: UUID

  public init(issueID: UUID) { self.issueID = issueID }
}

public struct ApplicationServiceRemappingProfileIssue: Codable, Equatable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable {
    case damagedProfile
    case unusableLibrary
  }

  public let id: UUID
  public let kind: Kind
  public let message: String

  public init(id: UUID, kind: Kind = .damagedProfile, message: String) {
    self.id = id
    self.kind = kind
    self.message = message
  }

  private enum CodingKeys: String, CodingKey { case id, kind, message }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .damagedProfile
    message = try container.decode(String.self, forKey: .message)
  }
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
    case expectedCurrent
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
    case vendorID
    case productID
  }
}

public struct ApplicationServiceJoyConPairArguments: Codable, Sendable {
  public let leftRuntimeIdentifier: String
  public let rightRuntimeIdentifier: String
  public let profileID: UUID

  public init(leftRuntimeIdentifier: String, rightRuntimeIdentifier: String, profileID: UUID) {
    self.leftRuntimeIdentifier = leftRuntimeIdentifier
    self.rightRuntimeIdentifier = rightRuntimeIdentifier
    self.profileID = profileID
  }

  private enum CodingKeys: String, CodingKey {
    case leftRuntimeIdentifier
    case rightRuntimeIdentifier
    case profileID
  }
}

public struct ApplicationServiceJoyConUnpairArguments: Codable, Sendable {
  public let sessionID: UUID

  public init(sessionID: UUID) { self.sessionID = sessionID }

  private enum CodingKeys: String, CodingKey { case sessionID }
}

public struct ApplicationServiceJoyConPairPayload: Codable, Equatable, Sendable {
  public let sessionID: UUID
  public let leftRuntimeIdentifier: String
  public let rightRuntimeIdentifier: String
  public let profileID: UUID
  public let profileName: String
  public let gyroSelection: RemappingJoyConGyroSelection

  public init(
    sessionID: UUID,
    leftRuntimeIdentifier: String,
    rightRuntimeIdentifier: String,
    profileID: UUID,
    profileName: String,
    gyroSelection: RemappingJoyConGyroSelection
  ) {
    self.sessionID = sessionID
    self.leftRuntimeIdentifier = leftRuntimeIdentifier
    self.rightRuntimeIdentifier = rightRuntimeIdentifier
    self.profileID = profileID
    self.profileName = profileName
    self.gyroSelection = gyroSelection
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID
    case leftRuntimeIdentifier
    case rightRuntimeIdentifier
    case profileID
    case profileName
    case gyroSelection
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
    case vendorID
    case productID
    case profileID
    case profileName
    case applicationScope
  }
}

extension Sequence where Element == ApplicationServiceRemappingActiveProfilePayload {
  /// Returns the entry routing uses for a model without a frontmost app: the last global-scope
  /// entry, otherwise the last entry.
  public func routingActiveProfile(
    vendorID: UInt16,
    productID: UInt16
  ) -> ApplicationServiceRemappingActiveProfilePayload? {
    let candidates = filter { $0.vendorID == vendorID && $0.productID == productID }
    return candidates.last { $0.applicationScope == .global } ?? candidates.last
  }
}

public enum ApplicationServiceRemappingRouteSelection: String, Codable, Sendable {
  case remapping
  case unavailable
  case virtualGamepad = "virtual-gamepad"
}

public enum ApplicationServiceRemappingRouteEligibility: String, Codable, Sendable {
  case eligible
  case outputSuppressed = "output_suppressed"
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  case physicalInputNotExclusive = "physical_input_not_exclusive"
  case unavailable
  case virtualOutputSuppressed = "virtual_output_suppressed"
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
    case vendorID
    case productID
    case runtimeIdentifier
    case selection
    case eligibility
    case activeProfileID
    case activeProfileName
    case applicationScope
    case frontmostBundleIdentifier
    case postEventAccess
    case failure
  }
}

public struct ApplicationServiceRemappingSnapshotPayload: Codable, Equatable, Sendable {
  public let profiles: [RemappingProfile]
  public let activeProfiles: [ApplicationServiceRemappingActiveProfilePayload]
  public let routes: [ApplicationServiceRemappingRoutePayload]
  public let joyConPairs: [ApplicationServiceJoyConPairPayload]
  public let profileIssues: [ApplicationServiceRemappingProfileIssue]
  public let postEventAccess: RemappingPostEventAccessState

  public init(
    profiles: [RemappingProfile],
    activeProfiles: [ApplicationServiceRemappingActiveProfilePayload],
    routes: [ApplicationServiceRemappingRoutePayload],
    joyConPairs: [ApplicationServiceJoyConPairPayload] = [],
    profileIssues: [ApplicationServiceRemappingProfileIssue] = [],
    postEventAccess: RemappingPostEventAccessState
  ) {
    self.profiles = profiles
    self.activeProfiles = activeProfiles
    self.routes = routes
    self.joyConPairs = joyConPairs
    self.profileIssues = profileIssues
    self.postEventAccess = postEventAccess
  }

  private enum CodingKeys: String, CodingKey {
    case profiles
    case activeProfiles
    case routes
    case joyConPairs
    case profileIssues
    case postEventAccess
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    profiles = try container.decode([RemappingProfile].self, forKey: .profiles)
    activeProfiles = try container.decode(
      [ApplicationServiceRemappingActiveProfilePayload].self,
      forKey: .activeProfiles
    )
    routes = try container.decode([ApplicationServiceRemappingRoutePayload].self, forKey: .routes)
    joyConPairs =
      try container.decodeIfPresent(
        [ApplicationServiceJoyConPairPayload].self,
        forKey: .joyConPairs
      ) ?? []
    profileIssues =
      try container.decodeIfPresent(
        [ApplicationServiceRemappingProfileIssue].self,
        forKey: .profileIssues
      ) ?? []
    postEventAccess = try container.decode(
      RemappingPostEventAccessState.self,
      forKey: .postEventAccess
    )
  }
}

/// A deterministic, code-bearing remapping failure carried in the RPC response `remappingError`.
public struct ApplicationServiceRemappingRPCError: Error, Codable, Equatable, LocalizedError,
  Sendable
{
  public enum Code: String, Codable, Sendable, CaseIterable {
    case controllerUnavailable = "controller_unavailable"
    case joyConPairUnavailable = "joy_con_pair_unavailable"
    case motionUnavailable = "motion_unavailable"
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
    case profileRecoveryRequired = "profile_recovery_required"
    case unwritableLibrary = "library_unwritable"
    case unexpected = "unexpected"
    case profileProducesNoOutput = "profile_produces_no_output"

    /// The stable error code of this failure, listed in `Resources/ErrorCodes.json`.
    public var errorCode: ErrorCode {
      switch self {
      case .controllerUnavailable: .controllerUnavailable
      case .joyConPairUnavailable: .joyConPairUnavailable
      case .motionUnavailable: .motionUnavailable
      case .argumentTooLarge: .argumentTooLarge
      case .corruptLibrary: .corruptLibrary
      case .duplicateName: .duplicateName
      case .invalidArguments: .invalidArguments
      case .invalidProfile: .invalidProfile
      case .librarySizeExceeded: .librarySizeExceeded
      case .profileAlreadyExists: .profileAlreadyExists
      case .profileUpdateConflict: .profileUpdateConflict
      case .profileCountExceeded: .profileCountExceeded
      case .profileNotFound: .profileNotFound
      case .responseEncodingFailed: .responseEncodingFailed
      case .responseTooLarge: .responseTooLarge
      case .routerEngineUnavailable: .routerEngineUnavailable
      case .routerLibraryAndEngineUnavailable: .routerLibraryAndEngineUnavailable
      case .routerLibraryUnavailable: .routerLibraryUnavailable
      case .routerShutDown: .routerShutDown
      case .transactionUnreconciled: .transactionUnreconciled
      case .unreadableLibrary: .unreadableLibrary
      case .profileRecoveryRequired: .profileRecoveryRequired
      case .unwritableLibrary: .unwritableLibrary
      case .unexpected: .remappingUnexpected
      case .profileProducesNoOutput: .profileProducesNoOutput
      }
    }
  }

  public let code: Code
  public let message: String

  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }

  public var errorDescription: String? { message }
}
