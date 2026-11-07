import Foundation

/// Byte limits on the messages of the remapping RPC methods.
///
/// Decoded remapping arguments stay below the framed envelope limit of the local transport.
public enum ApplicationServiceRemappingRPC {
  /// The largest framed message of the local transport, in bytes.
  public static let maximumTransportFrameBytes = 8 * 1_024 * 1_024
  /// The largest encoded remapping payload, in bytes.
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

/// A problem of the persisted remapping profiles that the snapshot reports.
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

  /// Creates a profile issue from its values.
  public init(id: UUID, kind: Kind = .damagedProfile, code: ErrorCode, message: String) {
    self.id = id
    self.kind = kind
    self.code = code
    self.message = message
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
  }

  /// Decodes the value from `decoder`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    kind = try container.decode(Kind.self, forKey: .kind)
    code = try container.decode(ErrorCode.self, forKey: .code)
    message = try container.decode(String.self, forKey: .message)
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

  /// Creates a pair payload from its values.
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

/// The active profile of one controller model, as the remapping snapshot lists it.
public struct ApplicationServiceRemappingActiveProfilePayload: Codable, Equatable, Sendable {
  /// The USB vendor ID of the controller model.
  public let vendorID: UInt16
  /// The USB product ID of the controller model.
  public let productID: UInt16
  /// The ID of the active profile.
  public let profileID: UUID
  /// The name of the active profile.
  public let profileName: String
  /// The apps in which the profile is active.
  public let applicationScope: RemappingApplicationScope

  /// Creates an active-profile payload from its values.
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

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `vendorID` key.
    case vendorID
    /// The `productID` key.
    case productID
    /// The `profileID` key.
    case profileID
    /// The `profileName` key.
    case profileName
    /// The `applicationScope` key.
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

/// Which output path routes a controller's input.
public enum ApplicationServiceRemappingRouteSelection: String, Codable, Sendable {
  /// The remapping engine produces the output.
  case remapping
  /// No output path is available.
  case unavailable
  /// The controller's virtual gamepad produces the output.
  case virtualGamepad = "virtual-gamepad"
}

/// Whether the route of a controller can produce remapped output now, and if not, why.
public enum ApplicationServiceRemappingRouteEligibility: String, Codable, Sendable {
  /// The route can produce output.
  case eligible
  /// Output is suppressed.
  case outputSuppressed = "output_suppressed"
  /// macOS has not granted the permission to post input events.
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  /// The profile targets an app that is not frontmost.
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  /// OJD does not hold the physical input exclusively.
  case physicalInputNotExclusive = "physical_input_not_exclusive"
  /// The route is unavailable.
  case unavailable
  /// The virtual gamepad's output is suppressed.
  case virtualOutputSuppressed = "virtual_output_suppressed"
}

/// A failure of the remapping engine that the route payload carries.
public struct ApplicationServiceRemappingFailurePayload: Codable, Equatable, Sendable {
  /// The failure's code.
  public let code: ApplicationServiceRemappingRPCError.Code
  /// A human-readable description of the failure.
  public let message: String

  /// Creates a failure payload from its values.
  public init(code: ApplicationServiceRemappingRPCError.Code, message: String) {
    self.code = code
    self.message = message
  }
}

/// How one controller's input is routed, as the remapping snapshot lists it.
public struct ApplicationServiceRemappingRoutePayload: Codable, Equatable, Sendable {
  /// The USB vendor ID of the controller model.
  public let vendorID: UInt16
  /// The USB product ID of the controller model.
  public let productID: UInt16
  /// The session token of the routed controller.
  public let sessionToken: ControllerSessionToken
  /// Which output path routes the controller.
  public let selection: ApplicationServiceRemappingRouteSelection
  /// Whether the route can produce output now.
  public let eligibility: ApplicationServiceRemappingRouteEligibility
  /// The ID of the active profile; nil when none is active.
  public let activeProfileID: UUID?
  /// The name of the active profile; nil when none is active.
  public let activeProfileName: String?
  /// The apps in which the active profile applies; nil when none is active.
  public let applicationScope: RemappingApplicationScope?
  /// The bundle identifier of the frontmost app; nil when it is unknown.
  public let frontmostAppID: String?
  /// The state of the macOS permission to post input events.
  public let postEventAccess: RemappingPostEventAccessState
  /// The failure that makes the route unavailable; nil when there is none.
  public let failure: ApplicationServiceRemappingFailurePayload?

  /// Creates a route payload from its values.
  public init(
    vendorID: UInt16,
    productID: UInt16,
    sessionToken: ControllerSessionToken,
    selection: ApplicationServiceRemappingRouteSelection,
    eligibility: ApplicationServiceRemappingRouteEligibility,
    activeProfileID: UUID?,
    activeProfileName: String?,
    applicationScope: RemappingApplicationScope?,
    frontmostAppID: String?,
    postEventAccess: RemappingPostEventAccessState,
    failure: ApplicationServiceRemappingFailurePayload?
  ) {
    self.vendorID = vendorID
    self.productID = productID
    self.sessionToken = sessionToken
    self.selection = selection
    self.eligibility = eligibility
    self.activeProfileID = activeProfileID
    self.activeProfileName = activeProfileName
    self.applicationScope = applicationScope
    self.frontmostAppID = frontmostAppID
    self.postEventAccess = postEventAccess
    self.failure = failure
  }

  /// The keys of the JSON encoding.
  private enum CodingKeys: String, CodingKey {
    /// The `vendorID` key.
    case vendorID
    /// The `productID` key.
    case productID
    /// The `sessionToken` key.
    case sessionToken
    /// The `selection` key.
    case selection
    /// The `eligibility` key.
    case eligibility
    /// The `activeProfileID` key.
    case activeProfileID
    /// The `activeProfileName` key.
    case activeProfileName
    /// The `applicationScope` key.
    case applicationScope
    /// The `frontmostAppID` key.
    case frontmostAppID
    /// The `postEventAccess` key.
    case postEventAccess
    /// The `failure` key.
    case failure
  }
}

/// A profile a mod package serves, and the package that serves it.
public struct ApplicationServiceRemappingPackageProfile: Codable, Equatable, Sendable {
  /// The ID of the profile.
  public let profileID: UUID
  /// The name of the package that serves the profile.
  public let package: String

  /// Creates the entry for the profile `profileID` served by `package`.
  public init(profileID: UUID, package: String) {
    self.profileID = profileID
    self.package = package
  }
}

/// The state of remapping that the service reports: the profiles, the active profile of each model,
/// the routes, the Joy-Con pairs and the profile issues.
public struct ApplicationServiceRemappingSnapshotPayload: Codable, Equatable, Sendable {
  /// Every profile in the library.
  public let profiles: [RemappingProfile]
  /// The active profile of each controller model.
  public let activeProfiles: [ApplicationServiceRemappingActiveProfilePayload]
  /// The route of each controller.
  public let routes: [ApplicationServiceRemappingRoutePayload]
  /// The Joy-Con pairs.
  public let joyConPairs: [ApplicationServiceJoyConPairPayload]
  /// The damaged profiles and library problems.
  public let profileIssues: [ApplicationServiceRemappingProfileIssue]
  /// The profiles in `profiles` that a package serves, sorted by profile id.
  public let packageProfiles: [ApplicationServiceRemappingPackageProfile]
  /// The state of the macOS permission to post input events.
  public let postEventAccess: RemappingPostEventAccessState

  /// Creates a snapshot from its values.
  public init(
    profiles: [RemappingProfile],
    activeProfiles: [ApplicationServiceRemappingActiveProfilePayload],
    routes: [ApplicationServiceRemappingRoutePayload],
    joyConPairs: [ApplicationServiceJoyConPairPayload] = [],
    profileIssues: [ApplicationServiceRemappingProfileIssue] = [],
    packageProfiles: [ApplicationServiceRemappingPackageProfile] = [],
    postEventAccess: RemappingPostEventAccessState
  ) {
    self.profiles = profiles
    self.activeProfiles = activeProfiles
    self.routes = routes
    self.joyConPairs = joyConPairs
    self.profileIssues = profileIssues
    self.packageProfiles = packageProfiles
    self.postEventAccess = postEventAccess
  }
}

/// A deterministic, code-bearing remapping failure carried in the RPC response `remappingError`.
public struct ApplicationServiceRemappingRPCError: Error, Codable, Equatable, LocalizedError,
  Sendable
{
  /// The code of a remapping failure on the wire.
  public enum Code: String, Codable, Sendable, CaseIterable {
    /// The selected controller is unavailable.
    case controllerUnavailable = "controller_unavailable"
    /// The Joy-Con pair cannot be formed or used.
    case joyConPairUnavailable = "joy_con_pair_unavailable"
    /// Motion calibration needs an eligible controller with motion samples.
    case motionUnavailable = "motion_unavailable"
    /// A request argument exceeds ``ApplicationServiceRemappingRPC/maximumArgumentBytes``.
    case argumentTooLarge = "argument_too_large"
    /// The profile library is corrupt.
    case corruptLibrary = "library_corrupt"
    /// Another profile has the name.
    case duplicateName = "duplicate_name"
    /// The request arguments are invalid.
    case invalidArguments = "invalid_arguments"
    /// The profile is not valid.
    case invalidProfile = "invalid_profile"
    /// The profile library exceeds its size limit.
    case librarySizeExceeded = "library_size_exceeded"
    /// A profile with the ID already exists.
    case profileAlreadyExists = "profile_already_exists"
    /// The stored profile differs from the one the update expected.
    case profileUpdateConflict = "profile_update_conflict"
    /// The library would exceed its profile count limit.
    case profileCountExceeded = "profile_count_exceeded"
    /// No profile has the ID.
    case profileNotFound = "profile_not_found"
    /// The service could not encode the response.
    case responseEncodingFailed = "response_encoding_failed"
    /// The response exceeds the transport's size limit.
    case responseTooLarge = "response_too_large"
    /// The remapping engine is unavailable.
    case routerEngineUnavailable = "router_engine_unavailable"
    /// Neither the profile library nor the remapping engine is available.
    case routerLibraryAndEngineUnavailable = "router_library_and_engine_unavailable"
    /// The profile library is unavailable.
    case routerLibraryUnavailable = "router_library_unavailable"
    /// The remapping router is shut down.
    case routerShutDown = "router_shut_down"
    /// A profile mutation failed and the service could not reconcile its state.
    case transactionUnreconciled = "transaction_unreconciled"
    /// The profile library cannot be read.
    case unreadableLibrary = "library_unreadable"
    /// A profile issue must be repaired before the request can succeed.
    case profileRecoveryRequired = "profile_recovery_required"
    /// The profile library cannot be written.
    case unwritableLibrary = "library_unwritable"
    /// The failure has no more specific code.
    case unexpected = "unexpected"
    /// The profile produces no output and the request did not allow an empty profile.
    case profileProducesNoOutput = "profile_produces_no_output"
    /// The Joy-Con pair's profile takes its gyro from the other controller.
    case motionGyroNotSelected = "motion_gyro_not_selected"
    /// Motion calibration needs an active remapping profile for the controller.
    case motionProfileInactive = "motion_profile_inactive"
    /// The controller's remapping session changed during the request.
    case motionSessionChanged = "motion_session_changed"
    /// A mod package serves the profile, so it cannot be changed here.
    case packageProfileReadOnly = "package_profile_read_only"
    /// An action needs Post Event access, which is not granted.
    case postEventAccessMissing = "post_event_access_missing"
    /// An action needs Automation access, which is not granted.
    case automationAccessMissing = "automation_access_missing"
    /// The profile has a missing or unsupported `apiVersion`.
    case unsupportedAPIVersion = "unsupported_api_version"

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
      case .unsupportedAPIVersion: .unsupportedAPIVersion
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
      case .motionGyroNotSelected: .motionGyroNotSelected
      case .motionProfileInactive: .motionProfileInactive
      case .motionSessionChanged: .motionSessionChanged
      case .packageProfileReadOnly: .packageProfileReadOnly
      case .postEventAccessMissing: .postEventAccessMissing
      case .automationAccessMissing: .automationAccessMissing
      }
    }
  }

  /// The failure's code.
  public let code: Code
  /// A human-readable description of the failure.
  public let message: String

  /// Creates a failure from its code and message.
  public init(code: Code, message: String) {
    self.code = code
    self.message = message
  }

  /// The description of the error for the user.
  public var errorDescription: String? { message }
}
