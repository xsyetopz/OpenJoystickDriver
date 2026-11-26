import Foundation
import OpenJoystickDriverKit

/// Reads controller descriptions and decides which profile, persona identity and backend an
/// ``AutomaticUserSpaceOutputDispatcher`` publishes for each controller.
///
/// The decisions are recorded in the dispatcher's ``AutomaticDispatcherLedger``.
/// - Note: `Sendable` because every stored property is immutable and `Sendable`.
final class AutomaticProfileResolver: Sendable {
  /// Records the descriptions, selections and identities.
  private let ledger: AutomaticDispatcherLedger
  /// Reports who holds the input of a controller.
  private let ownershipProvider:
    @Sendable (LogicalControllerID) async -> ControllerOwnershipObservation
  /// Describes every connected controller.
  private let descriptionsProvider:
    @Sendable () async -> [LogicalControllerID: ApplicationServiceDeviceDescription]
  /// Describes one controller; nil when it is not connected.
  private let descriptionProvider:
    @Sendable (LogicalControllerID) async -> ApplicationServiceDeviceDescription?
  /// Reports the session state of one controller.
  private let sessionStateProvider: @Sendable (LogicalControllerID) async -> ControllerSessionState?
  /// Builds the backend for a profile.
  private let builder: @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching
  /// Returns the profile that an override selects for a controller, or nil when it has none.
  private let overrideProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?
  /// The identity of the controller's custom persona, which `identityBuilder` publishes over the
  /// built-in descriptor.
  private let identityProvider:
    @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity?
  /// Builds the backend for a profile and a custom persona identity.
  private let identityBuilder:
    @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws -> any VirtualOutputDispatching

  /// Creates a resolver whose providers default to `deviceManager`; tests replace them.
  init(
    ledger: AutomaticDispatcherLedger,
    deviceManager: DeviceManager,
    ownershipProvider: (@Sendable (LogicalControllerID) async -> ControllerOwnershipObservation)?,
    builder: @escaping @Sendable (VirtualHIDProfileID) throws -> any VirtualOutputDispatching,
    descriptionsProvider:
      (@Sendable () async -> [LogicalControllerID: ApplicationServiceDeviceDescription])?,
    overrideProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualHIDProfileID?,
    identityProvider:
      @escaping @Sendable (ApplicationServiceDeviceDescription) -> VirtualPersona.Identity?,
    identityBuilder:
      (
        @Sendable (VirtualHIDProfileID, VirtualPersona.Identity) throws ->
          any VirtualOutputDispatching
      )?
  ) {
    self.ledger = ledger
    self.ownershipProvider =
      ownershipProvider ?? { identifier in await deviceManager.ownershipObservation(for: identifier)
      }
    self.descriptionsProvider =
      descriptionsProvider ?? {
        await deviceManager.connectedDeviceDescriptions().reduce(into: [:]) {
          $0[$1.logicalControllerID] = ApplicationServiceDeviceDescription(snapshot: $1)
        }
      }
    // Delivery looks up one controller per input report; building every description there
    // dominated runtime CPU.
    if let descriptionsProvider {
      self.descriptionProvider = { @Sendable identifier in
        await descriptionsProvider()[identifier]
      }
      self.sessionStateProvider = { @Sendable identifier in
        await descriptionsProvider()[identifier]?.sessionState
      }
    } else {
      self.descriptionProvider = { @Sendable identifier in
        await deviceManager.deviceDescription(for: identifier).map(
          ApplicationServiceDeviceDescription.init(snapshot:)
        )
      }
      self.sessionStateProvider = { @Sendable identifier in
        await deviceManager.controllerSessionState(for: identifier)
      }
    }
    self.builder = builder
    self.overrideProvider = overrideProvider
    self.identityProvider = identityProvider
    self.identityBuilder = identityBuilder ?? { profileID, _ in try builder(profileID) }
  }

  /// Builds a backend for the profile selected for a controller, with its persona identity.
  ///
  /// The identity is read when the backend is built, after selection recorded it.
  func factory(for identifier: LogicalControllerID) -> AutomaticDispatcherCoordinator.Factory {
    { [self] profileID in
      guard let identity = ledger.identity(for: identifier) else {
        return try builder(profileID)
      }
      return try identityBuilder(profileID, identity)
    }
  }

  /// Describes every connected controller.
  func descriptions() async -> [LogicalControllerID: ApplicationServiceDeviceDescription] {
    await descriptionsProvider()
  }

  /// Describes `identifier`; nil when it is not connected.
  func description(
    for identifier: LogicalControllerID
  ) async -> ApplicationServiceDeviceDescription? {
    await descriptionProvider(identifier)
  }

  /// The persona identity of the controller described by `description`.
  func identity(
    for description: ApplicationServiceDeviceDescription
  ) -> VirtualPersona.Identity? {
    identityProvider(description)
  }

  /// Returns the cached description of `identifier`, reading it first when it is not cached.
  func cachedDescription(
    for identifier: LogicalControllerID
  ) async -> ApplicationServiceDeviceDescription? {
    if let cached = ledger.cachedDescription(for: identifier) { return cached }
    let generation = ledger.cacheGeneration(for: identifier)
    guard let description = await descriptionProvider(identifier) else { return nil }
    ledger.storeDescription(description, for: identifier, generation: generation)
    return description
  }

  /// Whether `identifier` has an active session and the serving policy publishes `profile` for it.
  func isEligible(
    _ identifier: LogicalControllerID,
    profile: VirtualHIDProfileID
  ) async -> Bool {
    guard let description = await cachedDescription(for: identifier),
      await sessionStateProvider(identifier) == .active
    else { return false }
    var input = ServingInput(description, override: profile)
    input.observation = await ownershipProvider(identifier)
    return ServingPolicy.route(input).publishesVirtualDevice
  }

  /// The controller's selected profile; nil when no virtual profile can represent its declared
  /// controls, which leaves the controller without a virtual device.
  ///
  /// Selects only when the physical session has no selection yet. A change posts a status change
  /// from `sender`.
  func profile(
    for identifier: LogicalControllerID,
    description: ApplicationServiceDeviceDescription,
    generation: UInt64,
    notifying sender: AnyObject
  ) -> VirtualHIDProfileID? {
    if let selection = ledger.selection(for: identifier) { return selection.profileID }
    let selection = select(for: description)
    commit(
      selection,
      identity: identityProvider(description),
      for: identifier,
      generation: generation,
      notifying: sender
    )
    return selection?.profileID
  }

  /// The persona the serving policy decides OJD publishes for the controller, from its declared
  /// controls and its Advanced override; nil when no persona can represent it.
  func select(
    for description: ApplicationServiceDeviceDescription
  ) -> VirtualHIDProfileSelector.Selection? {
    ServingPolicy.publishedPersona(for: description, override: overrideProvider(description))
  }

  /// Records the controller's selection, or records it as unavailable when no profile can represent
  /// it so the status surfaces the failure instead of the dispatcher silently leaving the
  /// controller without a virtual device.
  ///
  /// A controller that stopped since `generation` was read keeps no entry. A change posts a status
  /// change from `sender`.
  func commit(
    _ selection: VirtualHIDProfileSelector.Selection?,
    identity: VirtualPersona.Identity?,
    for identifier: LogicalControllerID,
    generation: UInt64,
    notifying sender: AnyObject
  ) {
    let changed = ledger.commit(
      selection,
      identity: identity,
      for: identifier,
      generation: generation
    )
    if changed { NotificationCenter.postServiceStatusChanged(from: sender) }
  }
}
