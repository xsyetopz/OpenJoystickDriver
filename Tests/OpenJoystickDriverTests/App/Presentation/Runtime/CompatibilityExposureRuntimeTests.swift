import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

private final class ExposureBackendProbe: CompatibilityUserSpaceOutputDispatching,
  CompatibilityUserSpaceOutputControllerActivating, ControllerLifecycleListener, @unchecked Sendable
{
  private(set) var activations: [[DeviceIdentifier]] = []
  private(set) var dispatches = 0
  private(set) var stops = 0
  private(set) var closes = 0
  var suppressOutput = false
  var status: String { "probe" }
  var lastRumbleStatus: String { "none" }

  func activate(for identifiers: [DeviceIdentifier]) { activations.append(identifiers) }
  func activate(controller identifier: DeviceIdentifier) { activations.append([identifier]) }
  func dispatch(events _: [ControllerEvent], from _: DeviceIdentifier) { dispatches += 1 }
  func controllerDidStop(_: DeviceIdentifier) { stops += 1 }
  func close() { closes += 1 }
}

private final class ExposureState: @unchecked Sendable {
  var ownership: ControllerOwnershipObservation = .exclusiveRawUSB
  var descriptions: [ApplicationServiceDeviceDescription] = []
}

@Suite(.serialized) struct CompatibilityExposureRuntimeTests {
  private let identifier = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)

  private func gipDescription() -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "GIP",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      parser: "GIP",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .xboxOne,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
  }

  private func makeAdapter(
    identity: CompatibilityIdentity,
    state: ExposureState,
    backend: ExposureBackendProbe = ExposureBackendProbe()
  ) -> (CompatibilityUserSpaceOutputDispatchingAdapter, ExposureBackendProbe) {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    let adapter = CompatibilityUserSpaceOutputDispatchingAdapter(
      backend: backend,
      deviceManager: manager,
      identity: identity,
      descriptionsProvider: { state.descriptions },
      ownershipProvider: { _ in state.ownership }
    )
    return (adapter, backend)
  }

  @Test func explicitAppleIdentityPublishesForRawUSBGIP() async throws {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    let (adapter, backend) = makeAdapter(identity: .appleGameController, state: state)

    try await adapter.activate(controller: identifier)
    await adapter.dispatch(events: [], from: identifier)

    #expect(backend.activations == [[identifier]])
    #expect(backend.dispatches == 1)
  }

  @Test func explicitActivationAndLazyDispatchFailClosedWhenProfileOrDeviceIsUnavailable()
    async throws
  {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    let (adapter, backend) = makeAdapter(identity: .sdl2_3, state: state)

    try await adapter.activate(controller: identifier)
    await adapter.dispatch(events: [], from: identifier)
    #expect(backend.activations.isEmpty)
    #expect(backend.dispatches == 0)

    state.descriptions.removeAll()
    try await adapter.activate(controller: identifier)
    await adapter.dispatch(events: [], from: identifier)
    #expect(backend.activations.isEmpty)
    #expect(backend.dispatches == 0)
  }

  @Test func explicitIdentityContinuesPublishingWhenOwnershipIsUnknown() async throws {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    state.ownership = .unknown
    let (adapter, backend) = makeAdapter(identity: .appleGameController, state: state)

    try await adapter.activate(controller: identifier)
    await adapter.dispatch(events: [], from: identifier)

    #expect(backend.activations == [[identifier]])
    #expect(backend.dispatches == 1)
  }

  @Test func suppressionAndCloseForwardThroughAdapter() async {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    let (adapter, backend) = makeAdapter(identity: .appleGameController, state: state)

    await adapter.setOutputSuppressed(true)
    await adapter.controllerDidStop(identifier)
    await adapter.close()

    #expect(backend.suppressOutput)
    #expect(backend.stops == 1)
    #expect(backend.closes == 1)
  }

  @Test func automaticResolvedIdentityUsesTheSameEligibilityGate() async {
    let state = ExposureState()
    state.descriptions = [gipDescription()]
    let backend = ExposureBackendProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in state.ownership },
      consumerProvider: { .appleGameController },
      builder: { _ in backend },
      observeConsumerChanges: false,
      descriptionsProvider: { state.descriptions },
      identityProvider: { _, _ in .appleGameController }
    )

    await dispatcher.dispatch(events: [], from: identifier)
    #expect(backend.dispatches == 1)
    state.ownership = .unknown
    await dispatcher.dispatch(events: [], from: identifier)
    #expect(backend.dispatches == 2)
    await dispatcher.close()
  }
}
