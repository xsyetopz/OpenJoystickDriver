import Foundation
import OpenJoystickDriverKit

/// Applies physical ownership and compatibility-profile policy at the concrete backend boundary.
final class CompatibilityUserSpaceOutputDispatchingAdapter: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, ControllerLifecycleListener, @unchecked Sendable
{
  private let backend: any CompatibilityUserSpaceOutputDispatching
  private let deviceManager: DeviceManager
  private let ownershipProvider:
    @Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation
  private let identity: CompatibilityIdentity
  private let descriptionsProvider: @Sendable () async -> [ApplicationServiceDeviceDescription]

  init(
    backend: any CompatibilityUserSpaceOutputDispatching,
    deviceManager: DeviceManager,
    identity: CompatibilityIdentity,
    descriptionsProvider: @escaping @Sendable () async -> [ApplicationServiceDeviceDescription],
    ownershipProvider: (@Sendable (DeviceIdentifier) async -> ControllerOwnershipObservation)? = nil
  ) {
    self.backend = backend
    self.deviceManager = deviceManager
    self.ownershipProvider =
      ownershipProvider ?? { identifier in await deviceManager.ownershipObservation(for: identifier)
      }
    self.identity = identity
    self.descriptionsProvider = descriptionsProvider
  }

  var suppressOutput: Bool {
    get { backend.suppressOutput }
    set { backend.suppressOutput = newValue }
  }

  var status: String { backend.status }
  var lastRumbleStatus: String { backend.lastRumbleStatus }

  func activate(for identifiers: [DeviceIdentifier]) async throws {
    guard !identifiers.isEmpty else {
      try await backend.activate(for: [])
      return
    }
    let eligible = await eligibleIdentifiers(from: identifiers)
    guard !eligible.isEmpty else { return }
    if let activating = backend as? any CompatibilityUserSpaceOutputControllerActivating {
      for identifier in eligible { try await activating.activate(controller: identifier) }
    } else {
      try await backend.activate(for: eligible)
    }
  }

  func activate(controller identifier: DeviceIdentifier) async throws {
    guard await isEligible(identifier) else { return }
    if let activating = backend as? any CompatibilityUserSpaceOutputControllerActivating {
      try await activating.activate(controller: identifier)
    } else {
      try await backend.activate(for: [identifier])
    }
  }

  func setOutputSuppressed(_ suppressed: Bool) async {
    await backend.setOutputSuppressed(suppressed)
  }

  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    guard await isEligible(identifier) else { return }
    await backend.dispatch(events: events, from: identifier)
  }

  func controllerDidStop(_ identifier: DeviceIdentifier) async {
    if let listener = backend as? any ControllerLifecycleListener {
      await listener.controllerDidStop(identifier)
    }
  }

  func close() async { await backend.close() }

  private func eligibleIdentifiers(from identifiers: [DeviceIdentifier]) async -> [DeviceIdentifier]
  {
    var result: [DeviceIdentifier] = []
    for identifier in identifiers where await isEligible(identifier) { result.append(identifier) }
    return result
  }

  private func isEligible(_ identifier: DeviceIdentifier) async -> Bool {
    guard
      let description = await descriptionsProvider().first(where: {
        $0.runtimeIdentifier == identifier.runtimeIdentifier
      })
    else { return false }
    let ownership = await ownershipProvider(identifier)
    let available = CompatibilityProfileAvailabilityPolicy.isAvailable(
      identity,
      for: AutomaticCompatibilityResolver.resolve(for: description).subfamily
    )
    return ControllerExposureDecision.decide(
      ownership: ownership,
      intent: .explicit(identity),
      profileAvailable: available
    ).eligibility == .eligible
  }
}
