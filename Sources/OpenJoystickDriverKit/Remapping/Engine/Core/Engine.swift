import Foundation

/// Consumes normalized controller events and emits system and virtual gamepad actions.
///
/// The caller owns profile selection and target-application policy, and supplies the active profile
/// with each event. Gamepad destinations go through the injected virtual output sink. Time is
/// injected as monotonic uptime in nanoseconds, so turbo and continuous output can be tested
/// without sleeping.
public actor RemappingEventEngine {
  /// Sink for keyboard and pointer actions.
  let sink: any RemappingSystemInputSink
  /// Sink for virtual gamepad state, or `nil` when there is none.
  let gamepadSink: (any RemappingGamepadSink)?
  /// Sink for physical output claims, or `nil` when there is none.
  let physicalOutputSink: (any RemappingPhysicalOutputSink)?
  /// Receives profile switch requests, or `nil` when there is none.
  let profileSwitcher: (any RemappingProfileSwitching)?
  /// Performs system actions, or `nil` when there is none.
  let systemActionPerformer: (any RemappingSystemActionPerforming)?
  /// Receives each failure of a system action, which does not fault the engine.
  let reportSystemActionFailure: @Sendable (any Error) -> Void
  /// Controllers whose virtual gamepad state was sent and not yet neutralized.
  var heldGamepadDevices: Set<LogicalControllerID> = []
  /// Controllers whose virtual gamepad state may still be held after a failure.
  var uncertainGamepadDevices: Set<LogicalControllerID> = []
  /// Owners of the physical output claims that are held, by controller.
  var heldPhysicalOwners: [LogicalControllerID: Set<UUID>] = [:]
  /// Controllers whose physical output claims may still be held after a failure.
  var uncertainPhysicalDevices: Set<LogicalControllerID> = []
  /// Barrier that admits output operations.
  nonisolated public let emissionBarrier: RemappingEmissionBarrier
  /// Mapping state of all controllers.
  var state = RemappingEngineState()
  /// Whether a sink failure has stopped the engine until recovery succeeds.
  var faulted = false
  /// Whether an operation is running.
  var operationInProgress = false
  /// Operations waiting for the running one to finish, in arrival order.
  var operationWaiters: [CheckedContinuation<Void, Never>] = []
  /// Keyboard and pointer outputs that may still be held after a failure.
  var uncertainHeldOutputs: Set<RemappingHeldOutput> = []

  /// Creates an engine.
  /// - Parameters:
  ///   - sink: Receives keyboard and pointer actions.
  ///   - gamepadSink: Receives virtual gamepad state.
  ///   - physicalOutputSink: Receives physical output claims.
  ///   - profileSwitcher: Receives profile switch requests.
  ///   - systemActionPerformer: Performs system actions.
  ///   - reportSystemActionFailure: Receives the failure of a system action.
  ///   - emissionBarrier: Admits output operations.
  public init(
    sink: any RemappingSystemInputSink,
    gamepadSink: (any RemappingGamepadSink)? = nil,
    physicalOutputSink: (any RemappingPhysicalOutputSink)? = nil,
    profileSwitcher: (any RemappingProfileSwitching)? = nil,
    systemActionPerformer: (any RemappingSystemActionPerforming)? = nil,
    reportSystemActionFailure: @escaping @Sendable (any Error) -> Void = { _ in },
    emissionBarrier: RemappingEmissionBarrier = RemappingEmissionBarrier()
  ) {
    self.profileSwitcher = profileSwitcher
    self.systemActionPerformer = systemActionPerformer
    self.reportSystemActionFailure = reportSystemActionFailure
    self.sink = sink
    self.gamepadSink = gamepadSink
    self.physicalOutputSink = physicalOutputSink
    self.emissionBarrier = emissionBarrier
  }
}
