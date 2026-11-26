import Foundation
import OpenJoystickDriverKit

extension AutomaticDispatcherCoordinator {
  /// Decides whether a controller may publish a profile.
  typealias Eligibility = @Sendable (LogicalControllerID, VirtualHIDProfileID) async -> Bool
  /// Builds the backend that publishes a profile.
  typealias Factory = @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  /// The controller's selected profile; nil when no profile can represent it.
  typealias ProfileProvider =
    @Sendable (LogicalControllerID, ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?

  /// An installation request for a controller, valid only for the generations it carries.
  struct Request: Sendable {
    /// The controller that the backend publishes for.
    let controller: LogicalControllerID
    /// The identity of the request, which the installed backend records.
    let token: UUID
    /// The physical session generation that the request belongs to.
    let sessionGeneration: UInt64
    /// The publication generation that the request belongs to.
    let publicationGeneration: UInt64
    /// The profile to publish.
    let target: VirtualHIDProfileID
  }

  /// An installation in flight.
  struct Pending {
    /// The request that the task serves.
    let request: Request
    /// The task that builds, activates and installs the backend.
    let task: Task<Void, any Error>
  }

  /// The publication state of one controller.
  struct Entry {
    /// Physical-session state survives temporary publication pausing.
    var sessionGeneration: UInt64 = 0
    /// Whether the physical session is live.
    var physicalSessionActive = true
    /// Invalidates only virtual publication work for the current physical session.
    var publicationGeneration: UInt64 = 0
    /// The profile that the installed backend publishes.
    var target: VirtualHIDProfileID?
    /// How to publish again after a failure or a pause.
    var context: PublicationContext?
    /// The backend that publishes.
    var installed: AutomaticBackendSlot?
    /// The token of the request that installed the backend.
    var installedToken: UUID?
    /// The backend that is closing and must finish before another publishes.
    var retiring: AutomaticBackendSlot?
    /// The installation in flight that is current.
    var pending: Pending?
    /// Every installation in flight, by request token.
    var tasks: [UUID: Pending] = [:]
    /// The text of the last publication failure.
    var lastFailure: String?
    /// Where recovery stands: idle, retiring, waiting-for-retirement, retry-gated or recovering.
    var recoveryState = "idle"
    /// The identity of the scheduled retry, so a stale retry does nothing.
    var recoveryToken: UUID?
    /// Another client holds the controller's input; nothing installs until it lets go.
    var heldByAnotherClient = false

    /// Whether the physical session is live and both generations equal `generations`.
    func isCurrent(_ generations: (session: UInt64, publication: UInt64)) -> Bool {
      physicalSessionActive && sessionGeneration == generations.session
        && publicationGeneration == generations.publication
    }
  }

  /// What a controller needs to publish again without a caller.
  struct PublicationContext: Sendable {
    /// The profile to publish.
    let target: VirtualHIDProfileID
    /// Decides whether the controller may publish.
    let isEligible: Eligibility
    /// Builds the backend.
    let factory: Factory
  }
}
