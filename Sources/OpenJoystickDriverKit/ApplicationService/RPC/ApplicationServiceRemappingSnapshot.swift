public import Foundation

/// When a profile was last activated.
public struct ApplicationServiceRemappingProfileUse: Codable, Equatable, Sendable {
  /// The ID of the profile.
  public let profileID: UUID
  /// The time of the activation, in seconds since 1970.
  public let usedAt: Double

  /// Creates the entry for the profile `profileID` activated at `usedAt`.
  public init(profileID: UUID, usedAt: Double) {
    self.profileID = profileID
    self.usedAt = usedAt
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
/// each controller's road, the Joy-Con pairs and the profile issues.
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
  /// When each activated profile in `profiles` was last activated, sorted by profile id.
  public let lastUsed: [ApplicationServiceRemappingProfileUse]
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
    lastUsed: [ApplicationServiceRemappingProfileUse] = [],
    postEventAccess: RemappingPostEventAccessState
  ) {
    self.profiles = profiles
    self.activeProfiles = activeProfiles
    self.routes = routes
    self.joyConPairs = joyConPairs
    self.profileIssues = profileIssues
    self.packageProfiles = packageProfiles
    self.lastUsed = lastUsed
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
    /// An action needs to send keys while Secure Input blocks them.
    case secureInputEnabled = "secure_input_enabled"
    /// A system action failed.
    case systemActionFailed = "system_action_failed"
    /// The system refused to create the MIDI source of a MIDI action.
    case midiSourceRefused = "midi_source_refused"
    /// The profile has a missing or unsupported `apiVersion`.
    case unsupportedAPIVersion = "unsupported_api_version"

    /// The stable error code of this failure, listed in `Resources/ErrorCodes.plist`.
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
      case .secureInputEnabled: .secureInputEnabled
      case .systemActionFailed: .systemActionFailed
      case .midiSourceRefused: .midiSourceRefused
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
