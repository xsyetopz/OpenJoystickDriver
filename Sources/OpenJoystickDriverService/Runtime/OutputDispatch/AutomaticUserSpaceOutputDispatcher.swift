import Foundation
import OpenJoystickDriverKit

/// Publishes a user-space virtual gamepad per controller, choosing and replacing the profile of
/// each backend as the controller, its ownership and the personas change.
///
/// Each controller's backend is built on demand by the coordinator, so a controller with no profile
/// that can represent it publishes nothing and is reported through ``status``.
/// - Note: `@unchecked Sendable` because `ledger` guards every mutable property.
final class AutomaticUserSpaceOutputDispatcher: VirtualOutputDispatching,
  VirtualOutputControllerActivating, ControllerLifecycleListener, ControllerInputOwnershipListener,
  RemappingGamepadSink, RemappingGamepadOutputControlling, @unchecked Sendable
{
  /// Internal so tests can observe when a stop reaches the coordinator.
  let coordinator = AutomaticDispatcherCoordinator()
  /// Holds the mutable state of the dispatcher behind one lock.
  let ledger: AutomaticDispatcherLedger
  /// Reads descriptions and decides the profile, identity and backend of each controller.
  let resolver: AutomaticProfileResolver

  /// Creates a dispatcher over `deviceManager` that builds each backend with `builder`.
  ///
  /// The providers default to the device manager; tests replace them.
  ///
  /// - Parameters:
  ///   - deviceManager: The source of controllers, sessions and ownership.
  ///   - ownershipProvider: Reports who holds a controller's input.
  ///   - builder: Builds the backend for a profile.
  ///   - descriptionsProvider: Describes every connected controller.
  ///   - overrideProvider: Returns the profile that the Advanced override selects for a controller.
  ///   - identityProvider: Returns the custom persona identity of a controller.
  ///   - identityBuilder: Builds the backend for a profile with a custom identity; defaults to
  ///     `builder`, which ignores the identity.
  ///   - timingAnnouncementIntervalNanoseconds: The shortest time between two announcements that
  ///     only move the send timings.
  init(
    deviceManager: DeviceManager,
    ownershipProvider: (@Sendable (LogicalControllerID) async -> ControllerOwnershipObservation)? =
      nil,
    builder: @escaping @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching,
    descriptionsProvider:
      (@Sendable () async -> [LogicalControllerID: ApplicationServiceDeviceDescription])? = nil,
    overrideProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID? = { _ in nil
      },
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity? = { _ in
        nil
      },
    identityBuilder:
      (
        @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws ->
          any VirtualOutputDispatching
      )? = nil,
    timingAnnouncementIntervalNanoseconds: UInt64 = 1_000_000_000
  ) {
    let stateLedger = AutomaticDispatcherLedger(
      timingAnnouncementIntervalNanoseconds: timingAnnouncementIntervalNanoseconds
    )
    self.ledger = stateLedger
    self.resolver = AutomaticProfileResolver(
      ledger: stateLedger,
      deviceManager: deviceManager,
      ownershipProvider: ownershipProvider,
      builder: builder,
      descriptionsProvider: descriptionsProvider,
      overrideProvider: overrideProvider,
      identityProvider: identityProvider,
      identityBuilder: identityBuilder
    )
  }

  /// Whether all virtual output is paused.
  var suppressOutput: Bool {
    get { ledger.suppressOutput }
    set { ledger.suppressOutput = newValue }
  }

  /// Sets whether all virtual output is paused and applies it to the backends.
  func setOutputSuppressed(_ suppressed: Bool) async {
    suppressOutput = suppressed
    await synchronizeSuppression()
  }

  /// Applies the current pausing value to the coordinator and records it as applied.
  func synchronizeSuppression() async {
    await coordinator.synchronizeSuppression {
      self.ledger.takeSuppressionToApply()
    }
  }

  /// Sets whether remapping output is paused and applies it to the backends.
  func setRemappingOutputSuppressed(_ suppressed: Bool) async {
    ledger.setRemappingSuppressed(suppressed)
    await coordinator.synchronizeRemappingSuppression {
      self.ledger.remappingSuppressed
    }
  }

  /// The targets and publication state of the backends, as a status line.
  var status: VirtualOutputBackendStatus { ledger.status }

  /// Always nil: the automatic dispatcher reports no rumble status.
  var lastRumbleStatus: String? { nil }

  /// Records whether another client holds the input of `identifier`.
  func controllerInputOwnershipChanged(
    _ ownership: HIDInputOwnership,
    for identifier: LogicalControllerID
  ) async {
    await coordinator.setHeldByAnotherClient(ownership == .ownedByAnotherClient, for: identifier)
    await synchronizeDiagnostics()
  }

  /// Forgets the selection of `identifier` and stops its session.
  func controllerDidStop(_ identifier: LogicalControllerID) async {
    ledger.forget(identifier)
    await coordinator.stop(identifier)
    await synchronizeDiagnostics()
  }

  /// How the current profile of a controller was selected.
  ///
  /// Nil before selection or when no profile can represent the controller.
  func selectionSource(
    for identifier: LogicalControllerID
  ) -> VirtualHIDProfileSelector.Selection.Source? {
    ledger.selectionSource(for: identifier)
  }

  /// The current selection of `identifier`, and whether no profile can represent it.
  func profileState(
    for identifier: LogicalControllerID
  ) -> (selection: VirtualHIDProfileSelector.Selection?, unavailable: Bool) {
    ledger.profileState(for: identifier)
  }

  /// The publication state of `identifier` at the last delivery, activation, or stop; nil before
  /// the controller has a target profile.
  func publicationStatus(
    for identifier: LogicalControllerID
  ) -> ApplicationServicePublicationStatus? {
    ledger.publicationStatus(for: identifier)
  }

  /// The values the virtual gamepad of a controller last reported.
  ///
  /// Nil when no user-space virtual gamepad publishes it.
  func virtualOutputState(for identifier: LogicalControllerID) async -> VirtualGamepadState? {
    guard let backend = await coordinator.installedBackend(for: identifier) else { return nil }
    return (backend as? UserSpaceOutputDispatcher)?.virtualOutputState(for: identifier)
  }

  /// Closes the coordinator and clears the cache.
  func close() async {
    await coordinator.close()
    ledger.removeAllDescriptions()
  }
}
