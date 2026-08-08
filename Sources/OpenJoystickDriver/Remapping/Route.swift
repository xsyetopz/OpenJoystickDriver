import Foundation
import OpenJoystickDriverKit

enum RemappingOutputRoutingError: Error, Equatable, LocalizedError, Sendable {
  case engine(RemappingEventEngineError)
  case library(RemappingProfileLibraryError)
  case libraryAndEngine(RemappingProfileLibraryError, RemappingEventEngineError)
  case profileTransactionAlreadyActive
  case profileTransactionUnreconciled(String)
  case profileTransactionViolation
  case shutDown

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

enum RemappingRouteSelection: Equatable, Sendable {
  case compatibility
  case remapping(profileID: UUID)
  case unavailable
}

enum RemappingRouteEligibility: String, Equatable, Sendable {
  case compatibilityOutputSuppressed = "compatibility_output_suppressed"
  case eligible
  case outputSuppressed = "output_suppressed"
  case postEventAccessNotAuthorized = "post_event_access_not_authorized"
  case targetApplicationNotFrontmost = "target_application_not_frontmost"
  case unavailable
}

struct RemappingRouteStatus: Equatable, Sendable {
  let identifier: DeviceIdentifier
  let selection: RemappingRouteSelection
  let eligibility: RemappingRouteEligibility
  let activeProfileID: UUID?
  let activeProfileName: String?
  let applicationScope: RemappingApplicationScope?
  let frontmostBundleIdentifier: String?
  let postEventAccessState: RemappingPostEventAccessState
  let error: RemappingOutputRoutingError?
}

struct RemappingRoutingControls: Equatable, Sendable {
  let outputSuppressed: Bool
  let compatibilityOutputAllowed: Bool
  let revision: UInt64
}

struct RemappingSchedulingSnapshot: Equatable, Sendable {
  let revision: UInt64
  let nextTickUptimeNanoseconds: UInt64?
}

struct RemappingProfileTransaction: Equatable, Hashable, Sendable {
  let id: UUID

  init() { id = UUID() }
}

struct RemappingRouterStatusSnapshot: Equatable, Sendable {
  let routes: [RemappingRouteStatus]
  let postEventAccessState: RemappingPostEventAccessState
}

enum RemappingProfileTransactionState: Equatable, Sendable {
  case inactive
  case active(RemappingProfileTransaction)
  case unreconciled(RemappingProfileTransaction, RemappingOutputRoutingError)

  var blocksOutput: Bool { self != .inactive }
}

enum RemappingSelectedRoute: Equatable, Sendable {
  case compatibility
  case remapping(RemappingProfile)
  case unavailable(RemappingOutputRoutingError)

  var profile: RemappingProfile? {
    guard case .remapping(let profile) = self else { return nil }
    return profile
  }
}

struct RemappingControllerRoute: Equatable, Sendable {
  var selection: RemappingSelectedRoute
  var eligibilitySnapshot: RemappingEligibilitySnapshot
  var error: RemappingOutputRoutingError?

  var eligibility: RemappingRouteEligibility {
    get { eligibilitySnapshot.eligibility }
    set {
      eligibilitySnapshot = RemappingEligibilitySnapshot(
        eligibility: newValue,
        environment: RemappingEligibilityEnvironment(
          frontmostBundleIdentifier: eligibilitySnapshot.frontmostBundleIdentifier,
          postEventAccessState: eligibilitySnapshot.postEventAccessState
        )
      )
    }
  }
}

struct RemappingEligibilitySnapshot: Equatable, Sendable {
  let eligibility: RemappingRouteEligibility
  let frontmostBundleIdentifier: String?
  let postEventAccessState: RemappingPostEventAccessState

  init(eligibility: RemappingRouteEligibility, environment: RemappingEligibilityEnvironment) {
    self.eligibility = eligibility
    self.frontmostBundleIdentifier = environment.frontmostBundleIdentifier
    self.postEventAccessState = environment.postEventAccessState
  }
}

struct RemappingEligibilityEnvironment {
  let frontmostBundleIdentifier: String?
  let postEventAccessState: RemappingPostEventAccessState
}

enum RemappingRoutingCheckpoint: Equatable, Sendable {
  case apply
  case dispatch
  case installRoutes
  case tick
}
