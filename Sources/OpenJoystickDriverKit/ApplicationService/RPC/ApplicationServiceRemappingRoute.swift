public import Foundation

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

  /// Creates an active-profile data from its values.
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

/// Which road a controller's input takes to become output.
public enum ApplicationServiceRemappingRouteSelection: String, Codable, Sendable {
  /// The remapping engine produces the output.
  case remapping
  /// No output path is available.
  case unavailable
  /// The controller's virtual gamepad produces the output.
  case virtualGamepad = "virtual-gamepad"
}

/// Whether a controller's road can make remapped output right now, and if not, why.
public enum ApplicationServiceRemappingRouteEligibility: String, Codable, Sendable {
  /// The road can make output.
  case eligible
  /// Output is paused.
  case outputSuppressed = "output_suppressed"
  /// macOS has not granted the permission to post input events.
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  /// The profile targets an app that is not frontmost.
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  /// OJD does not hold the physical input exclusively.
  case physicalInputNotExclusive = "physical_input_not_exclusive"
  /// The road is closed.
  case unavailable
  /// The virtual gamepad's output is paused.
  case virtualOutputSuppressed = "virtual_output_suppressed"
}

/// A remapping engine failure, sent along with the road's details.
public struct ApplicationServiceRemappingFailurePayload: Codable, Equatable, Sendable {
  /// The failure's code.
  public let code: ApplicationServiceRemappingRPCError.Code
  /// A human-readable description of the failure.
  public let message: String

  /// Creates a failure data from its values.
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

  /// Creates a route data from its values.
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
