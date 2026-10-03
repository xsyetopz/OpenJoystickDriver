import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  func provider(
    _ values: [ApplicationServiceDeviceDescription]
  ) -> @Sendable () async -> [ApplicationServiceDeviceDescription] { { values } }

  func description(_ id: DeviceIdentifier) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "probe",
      vendorID: id.controllerIdentity.vendorID,
      productID: id.controllerIdentity.productID,
      protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: id.runtimeIdentifier,
      unitIdentifier: id.unitIdentifier
    )
  }

  func description(
    _ id: DeviceIdentifier,
    binding: ProtocolBindingID
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "probe",
      vendorID: id.controllerIdentity.vendorID,
      productID: id.controllerIdentity.productID,
      protocolBinding: binding,
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      capabilities: ControllerCapabilities(controls: ControlID.xboxLayout),
      runtimeIdentifier: id.runtimeIdentifier
    )
  }

  @Test


  func automaticActivationBuildsOneCoherentChildPerController() async throws {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
    ]
    let created = AutomaticBackendBox()
    let descriptions = identifiers.map { description($0) }
    let descriptionsProvider: @Sendable () -> [ApplicationServiceDeviceDescription] = {
      descriptions
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in
        let backend = AutomaticBackendProbe()

        created.created.append(backend)
        return backend
      },
      descriptionsProvider: descriptionsProvider
    )

    try await dispatcher.activate(for: identifiers)
    #expect(created.created.count == identifiers.count)
    #expect(created.created.map(\.activations) == identifiers.map { [[$0]] })
    await dispatcher.activateOutput(for: identifiers[0])
    await dispatcher.close()
    #expect(created.created.allSatisfy { $0.closed })
  }

  @Test
  func automaticActivationFailureClosesTheEntireChildSet() async {
    let identifiers = [
      DeviceIdentifier(vendorID: 1, productID: 2), DeviceIdentifier(vendorID: 3, productID: 4),
    ]
    let created = AutomaticBackendBox()
    let descriptions = identifiers.map { description($0) }
    let descriptionsProvider: @Sendable () -> [ApplicationServiceDeviceDescription] = {
      descriptions
    }
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in
        let backend = AutomaticBackendProbe(failsActivation: created.created.count == 1)
        created.created.append(backend)
        return backend
      },
      descriptionsProvider: descriptionsProvider
    )

    do {
      try await dispatcher.activate(for: identifiers)
      Issue.record("Activation unexpectedly succeeded")
    } catch {}
    #expect(created.created.count == identifiers.count)
    #expect(created.created.allSatisfy { $0.closed })
    await dispatcher.close()
  }

  @Test


  func concurrentFirstDispatchCoalescesAndKeepsBothEvents() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(id)])
    )
    let first = Task { await dispatcher.activateOutput(for: id) }
    await probe.waitForEntered()
    let second = Task { await dispatcher.activateOutput(for: id) }

    #expect(probe.snapshot().0 == 0)
    probe.gate?.signal()
    await first.value
    await second.value
    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2[0].counts().0 == 2)
    #expect(probe.snapshot().2[0].counts().1 == 0)
    await dispatcher.close()
    #expect(probe.snapshot().2[0].counts().1 == 1)
  }

  @Test(.timeLimit(.minutes(1)))
  func differentControllersBuildIndependently() async {
    let first = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let second = DeviceIdentifier(vendorID: 0x3537, productID: 0x1011)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(

      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(first), description(second)])
    )
    let firstTask = Task { await dispatcher.activateOutput(for: first) }

    let secondTask = Task { await dispatcher.activateOutput(for: second) }
    await probe.waitForEntered()
    await probe.waitForEntered()
    #expect(probe.snapshot().1 == 2)
    probe.gate?.signal()
    probe.gate?.signal()
    await firstTask.value
    await secondTask.value
    #expect(probe.snapshot().0 == 2)
    await dispatcher.close()
  }

  @Test


  func stopDuringBuildDoesNotResurrect() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(id)])
    )
    let task = Task { await dispatcher.activateOutput(for: id) }
    await probe.waitForEntered()
    let stop = Task { await dispatcher.controllerDidStop(id) }
    // Release the build only after the stop has advanced the session; otherwise the build can
    // finish first and legitimately activate before the stop closes it.
    while !(await dispatcher.coordinator.publicationDiagnostics()).contains(where: {
      $0.contains("session=1,")
    }) { await Task.yield() }
    #expect(probe.snapshot().2.isEmpty)
    probe.gate?.signal()
    await stop.value
    await task.value
    let counts = probe.snapshot().2.first?.counts()
    #expect(counts?.0 == 0)
    #expect(counts?.1 == 1)
    await dispatcher.close()
  }

  @Test
  func closeDuringBuildClosesExactlyOnce() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    probe.gate = DispatchSemaphore(value: 0)
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(id)])
    )
    let task = Task { await dispatcher.activateOutput(for: id) }
    await probe.waitForEntered()
    let close = Task { await dispatcher.close() }
    #expect(probe.snapshot().2.isEmpty)
    probe.gate?.signal()
    await close.value
    await task.value
    #expect(probe.snapshot().2.first?.counts().1 == 1)
  }

  @Test
  func retiredLeaseClosesAfterReleaseOnlyOnce() async {
    let backend = ConcurrentBackendProbe()
    let slot = AutomaticBackendSlot(backend)
    let lease = slot.acquire()
    let retirement = Task { await slot.retireAndWait() }
    #expect(backend.counts().1 == 0)
    await lease?.release()
    _ = await retirement.value
    #expect(backend.counts().1 == 1)
  }

  @Test


  func suppressionRetiresPublicationThenRecreatesAndResumesOutput() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.activateOutput(for: id)
    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2.first?.counts().0 == 1)

    await dispatcher.setOutputSuppressed(true)
    #expect(probe.snapshot().2.first?.counts().1 == 1)
    await dispatcher.activateOutput(for: id)
    #expect(probe.snapshot().0 == 1)

    await dispatcher.setOutputSuppressed(false)
    #expect(probe.snapshot().0 == 2)
    #expect(probe.snapshot().2[1].counts().0 == 0)
    await dispatcher.activateOutput(for: id)
    #expect(probe.snapshot().2[1].counts().0 == 1)

    await dispatcher.close()
    #expect(probe.snapshot().2[1].counts().1 == 1)
  }

}
