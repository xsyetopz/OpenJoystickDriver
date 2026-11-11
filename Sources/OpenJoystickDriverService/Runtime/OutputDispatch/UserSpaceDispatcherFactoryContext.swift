import Foundation
import OpenJoystickDriverKit

/// Server-owned collaborators that a user-space dispatcher factory wires into what it builds.
struct UserSpaceDispatcherFactoryContext: Sendable {
  /// The source of controllers and their sessions.
  let deviceManager: DeviceManager
  /// The gate for the feedback of the virtual gamepad.
  let feedbackGate: VirtualOutputFeedbackGate
  /// The store of the Advanced profile overrides.
  let profileOverrides: VirtualHIDProfileOverrideStore
  /// The time limits of a transition.
  let timeouts: VirtualOutputTransitionTimeouts
  /// The clock of a transition.
  let clock: VirtualOutputTransitionClock
}

/// Builds one user-space dispatcher candidate for `ApplicationServiceServer` to activate.
typealias UserSpaceDispatcherFactory =
  @Sendable (UserSpaceDispatcherFactoryContext) throws -> any VirtualOutputDispatching
