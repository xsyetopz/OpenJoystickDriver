import Foundation
import OpenJoystickDriverKit

/// The failure of a remapping route, from the profile library, the event engine or the profile
/// transaction.
enum RemappingOutputRoutingError: Error, Equatable, LocalizedError, Sendable {
  /// The event engine failed.
  case engine(RemappingEventEngineError)
  /// The profile library failed.
  case library(RemappingProfileLibraryError)
  /// Both the profile library and the event engine failed.
  case libraryAndEngine(RemappingProfileLibraryError, RemappingEventEngineError)
  /// A profile transaction is already active.
  case profileTransactionAlreadyActive
  /// A profile transaction could not be reconciled, with the detail; output stays suspended.
  case profileTransactionUnreconciled(String)
  /// The transaction token is not the active one.
  case profileTransactionViolation
  /// The router has shut down.
  case shutDown

  /// The text that explains the failure to a user.
  var errorDescription: String? {
    switch self {
    case .engine(let error): error.localizedDescription
    case .library(let error): error.localizedDescription
    case .libraryAndEngine(let libraryError, let engineError):
      "\(libraryError.localizedDescription) \(engineError.localizedDescription)"
    case .profileTransactionAlreadyActive: "A remapping profile transaction is already active."
    case .profileTransactionUnreconciled(let detail):
      "Remapping output remains suspended because a profile transaction could not be "
        + "reconciled. \(detail)"
    case .profileTransactionViolation: "The remapping profile transaction token is invalid."
    case .shutDown: "The remapping output router has shut down."
    }
  }
}

/// The output that a controller uses, as ``RemappingOutputRouter`` reports it.
enum RemappingRouteSelection: Equatable, Sendable {
  /// The virtual gamepad output.
  case virtualGamepad
  /// The remapping profile `profileID`.
  case remapping(profileID: UUID)
  /// No output.
  case unavailable
}

/// Why a route does or does not emit, with the raw value that status output shows.
enum RemappingRouteEligibility: String, Equatable, Sendable {
  /// The route may emit.
  case eligible
  /// The router suppresses output.
  case outputSuppressed = "output_suppressed"
  /// The profile needs post-event access, which is not authorized.
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  /// The profile applies to an application that is not in front.
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  /// The profile needs exclusive input, but the device is not exclusive.
  case physicalInputNotExclusive = "physical_input_not_exclusive"
  /// The route has no output.
  case unavailable
  /// The virtual output is suppressed.
  case virtualOutputSuppressed = "virtual_output_suppressed"
}

/// The route of one controller, as status output shows it.
struct RemappingRouteStatus: Equatable, Sendable {
  /// The controller.
  let identifier: LogicalControllerID
  /// The selected output.
  let selection: RemappingRouteSelection
  /// Why the route does or does not emit.
  let eligibility: RemappingRouteEligibility
  /// The ID of the active remapping profile, when there is one.
  let activeProfileID: UUID?
  /// The name of the active remapping profile, when there is one.
  let activeProfileName: String?
  /// The applications that the active profile applies to, when there is one.
  let applicationScope: RemappingApplicationScope?
  /// The bundle ID of the frontmost application, when it is known.
  let frontmostAppID: String?
  /// The post-event access state that the eligibility was computed with.
  let postEventAccessState: RemappingPostEventAccessState
  /// The failure that made the route unavailable, if any.
  let error: RemappingOutputRoutingError?
}

/// The router-wide output controls.
struct RemappingRoutingControls: Equatable, Sendable {
  /// Whether the router suppresses all remapping output.
  let outputSuppressed: Bool
  /// The number of changes to the controls.
  let revision: UInt64
}

/// What the router's ticker needs to schedule its next tick.
struct RemappingSchedulingSnapshot: Equatable, Sendable {
  /// The number of changes that affect scheduling.
  let revision: UInt64
  /// The uptime in nanoseconds of the next tick, or nil when no tick is due.
  let nextTickUptimeNanoseconds: UInt64?
}

/// The token of one profile transaction.
struct RemappingProfileTransaction: Equatable, Hashable, Sendable {
  /// The unique ID of the transaction.
  let id: UUID

  /// Creates a token with a fresh ID.
  init() { id = UUID() }
}

/// A snapshot of the router's routes and Joy-Con pairs.
struct RemappingRouterStatusSnapshot: Equatable, Sendable {
  /// The route of every controller.
  let routes: [RemappingRouteStatus]
  /// The paired Joy-Con sessions.
  let joyConPairs: [RemappingJoyConPairSession]
  /// The post-event access state.
  let postEventAccessState: RemappingPostEventAccessState
}

/// The failure to pair two Joy-Cons.
enum RemappingJoyConPairError: Error, Equatable, LocalizedError, Sendable {
  /// A selected Joy-Con is not connected.
  case controllerUnavailable
  /// The selection is not one left and one right Joy-Con.
  case invalidControllerSide
  /// A selected Joy-Con already belongs to a pair.
  case memberAlreadyPaired
  /// The profile is not configured for paired Joy-Cons.
  case profileNotPairable
  /// The pair session does not exist.
  case sessionUnavailable

  /// The text that explains the failure to a user.
  var errorDescription: String? {
    switch self {
    case .controllerUnavailable:
      "Both selected Joy-Cons must be connected."
    case .invalidControllerSide: "Select one left Joy-Con and one right Joy-Con."
    case .memberAlreadyPaired: "A selected Joy-Con already belongs to a paired session."
    case .profileNotPairable: "The selected profile is not configured for paired Joy-Cons."
    case .sessionUnavailable: "The paired Joy-Con session is no longer available."
    }
  }
}

/// One pair of a left and a right Joy-Con that a profile treats as a single controller.
struct RemappingJoyConPairSession: Equatable, Sendable {
  /// The unique ID of the session.
  let id: UUID
  /// The left Joy-Con.
  let left: LogicalControllerID
  /// The right Joy-Con.
  let right: LogicalControllerID
  /// The profile that the pair uses.
  let profile: RemappingProfile

  /// Both members, left first.
  var members: [LogicalControllerID] { [left, right] }
}

/// Whether a profile transaction is in progress.
enum RemappingProfileTransactionState: Equatable, Sendable {
  /// No transaction is in progress.
  case inactive
  /// The transaction is in progress.
  case active(RemappingProfileTransaction)
  /// The transaction ended without reconciling, with the failure.
  case unreconciled(RemappingProfileTransaction, RemappingOutputRoutingError)

  /// Whether output is blocked: true unless the state is inactive.
  var blocksOutput: Bool { self != .inactive }
}

/// The output that the router selected for a controller.
enum RemappingSelectedRoute: Equatable, Sendable {
  /// The virtual gamepad output.
  case virtualGamepad
  /// The remapping profile.
  case remapping(RemappingProfile)
  /// No output, with the failure that caused it.
  case unavailable(RemappingOutputRoutingError)

  /// The remapping profile, or nil for another selection.
  var profile: RemappingProfile? {
    guard case .remapping(let profile) = self else { return nil }
    return profile
  }
}

/// The router's state for one controller.
struct RemappingControllerRoute: Equatable, Sendable {
  /// The selected output.
  var selection: RemappingSelectedRoute
  /// The eligibility with the environment that it was computed in.
  var eligibilitySnapshot: RemappingEligibilitySnapshot
  /// The failure of the route, if any.
  var error: RemappingOutputRoutingError?

  /// The eligibility of the snapshot; setting it keeps the snapshot's environment.
  var eligibility: RemappingRouteEligibility {
    get { eligibilitySnapshot.eligibility }
    set {
      eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: newValue,
        environment: RemappingEligibilityEnvironment(
          frontmostAppID: eligibilitySnapshot.frontmostAppID,
          postEventAccessState: eligibilitySnapshot.postEventAccessState
        )
      )
    }
  }
}

/// An eligibility together with the environment it was computed in.
struct RemappingEligibilitySnapshot: Equatable, Sendable {
  /// Why the route does or does not emit.
  let eligibility: RemappingRouteEligibility
  /// The bundle ID of the frontmost application, when it is known.
  let frontmostAppID: String?
  /// The post-event access state.
  let postEventAccessState: RemappingPostEventAccessState

  /// Creates the snapshot from `eligibility` and the values of `environment`.
  init(eligibility: RemappingRouteEligibility, environment: RemappingEligibilityEnvironment) {
    self.eligibility = eligibility
    self.frontmostAppID = environment.frontmostAppID
    self.postEventAccessState = environment.postEventAccessState
  }
}

/// What the eligibility of a route depends on besides the profile.
struct RemappingEligibilityEnvironment {
  /// The bundle ID of the frontmost application, when it is known.
  let frontmostAppID: String?
  /// The post-event access state.
  let postEventAccessState: RemappingPostEventAccessState
}

/// A stage of a routing operation, at which a test can pause it.
enum RemappingRoutingCheckpoint: Equatable, Sendable {
  /// Applying a profile.
  case apply
  /// Dispatching an input.
  case dispatch
  /// Installing the routes.
  case installRoutes
  /// A tick.
  case tick
}

/// Controllers whose input a remapping route consumes, readable per input report without
/// entering the routing actor.
final class RemappingObservedInputDemand: Sendable {
  /// The identifiers in the set.
  private let identifiers = Locked<Set<LogicalControllerID>>([])

  /// Tells whether `identifier` is in the set.
  func contains(_ identifier: LogicalControllerID) -> Bool {
    self.identifiers.withLock { $0.contains(identifier) }
  }

  /// Replaces the set with `identifiers`.
  func replace(with identifiers: Set<LogicalControllerID>) {
    self.identifiers.withLock { $0 = identifiers }
  }
}
