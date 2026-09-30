import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

extension VirtualOutputTests {
  @Test
  func unrelatedControllerStopLeavesOtherControllerUsable() async {
    let first = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let second = DeviceIdentifier(vendorID: 0x3537, productID: 0x1011)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(first), description(second)])
    )
    await dispatcher.activateOutput(for: second)
    await dispatcher.controllerDidStop(first)
    await dispatcher.activateOutput(for: second)
    #expect(probe.snapshot().2.first?.counts().0 == 2)
    await dispatcher.close()
  }

  /// System sleep stops every controller session, and wake starts the same controller again.
  @Test
  func sameControllerPublishesAgainAfterItsSessionStops() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010, locationID: 0x0013_0000)
    let log = AutomaticProfileLog()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { log.record($0) },
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.activateOutput(for: id)
    await dispatcher.controllerDidStop(id)
    await dispatcher.activateOutput(for: id)
    #expect(log.profiles().count == 2)
    #expect(dispatcher.status.wireValue.contains("targets:"))
    await dispatcher.close()
  }

  @Test
  func stoppingDuringAnInFlightDescriptionLookupDoesNotRepopulateItsCache() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let deviceDescription = description(id)
    let gate = DescriptionLookupGate()
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: {
        await gate.recordLookup()
        await gate.waitForRelease()
        return [deviceDescription]
      }
    )
    let activation = Task { await dispatcher.activateOutput(for: id) }
    await gate.waitForFirstLookup()
    await dispatcher.controllerDidStop(id)
    await gate.release()
    await activation.value

    await dispatcher.activateOutput(for: id)
    // A description lookup by each activation, then the eligibility check of the second
    // activation, which publishes a new session. A repopulated cache would skip the second lookup.
    #expect(await gate.lookupCount() == 3)
    await dispatcher.close()
  }

  @Test
  func automaticBuildsTheXboxProfileForTheXboxLayout() async {
    let id = DeviceIdentifier(vendorID: 0x045E, productID: 0x0B12)
    let log = AutomaticProfileLog()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { log.record($0) },
      descriptionsProvider: provider([
        description(id, binding: ProtocolBindingID(.xboxGIP, variant: .usb))
      ])
    )
    await dispatcher.activateOutput(for: id)
    #expect(log.profiles() == [.xboxOneSBluetooth])
    await dispatcher.close()
  }

  @Test
  func automaticProfileIgnoresTheProtocolBinding() async {
    let gip = DeviceIdentifier(vendorID: 0x045E, productID: 0x0B12)
    let sony = DeviceIdentifier(vendorID: 0x054C, productID: 0x09CC)
    let log = AutomaticProfileLog()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { log.record($0) },
      descriptionsProvider: provider([
        description(gip, binding: ProtocolBindingID(.xboxGIP, variant: .usb)),
        description(sony, binding: ProtocolBindingID(.sonyDualShock4, variant: .usb)),
      ])
    )
    await dispatcher.activateOutput(for: gip)
    await dispatcher.activateOutput(for: sony)
    let profiles = log.profiles()
    #expect(profiles.count == 2)
    #expect(Set(profiles).count == 1)
    await dispatcher.close()
  }

  @Test
  func automaticStatusNamesTheInstalledProfile() async {
    let id = DeviceIdentifier(vendorID: 0x045E, productID: 0x0B12)
    let log = AutomaticProfileLog()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { log.record($0) },
      descriptionsProvider: provider([
        description(id, binding: ProtocolBindingID(.xboxGIP, variant: .usb))
      ])
    )
    await dispatcher.activateOutput(for: id)
    #expect(dispatcher.status.wireValue.contains("targets: hid-xbox-one-s-bt"))
    #expect(!dispatcher.status.wireValue.contains("consumer:"))
    await dispatcher.close()
  }

  @Test
  func repeatedDispatchReusesTheBackendUntilControllerStops() async {
    let id = DeviceIdentifier(vendorID: 0x3537, productID: 0x1010)
    let probe = ConcurrentFactoryProbe()
    let dispatcher = AutomaticUserSpaceOutputDispatcher(
      deviceManager: DeviceManager(dispatcher: LoggingOutputDispatcher()),
      ownershipProvider: { _ in .exclusiveRawUSB },
      builder: { _ in probe.make() },
      descriptionsProvider: provider([description(id)])
    )
    await dispatcher.activateOutput(for: id)
    await dispatcher.activateOutput(for: id)
    #expect(probe.snapshot().0 == 1)
    #expect(probe.snapshot().2[0].counts() == (2, 0))

    await dispatcher.controllerDidStop(id)
    #expect(probe.snapshot().2[0].counts().1 == 1)
    #expect(!dispatcher.status.wireValue.contains("targets:"))
    await dispatcher.close()
  }

  @Test
  func coalescingStressRunsTwentyFiveIterations() async {
    for _ in 0..<25 {
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
      await dispatcher.close()
      #expect(probe.snapshot().2[0].counts().1 == 1)
    }
  }
}

/// Suspends a description lookup until released, so a test can stop a controller while its
/// description fetch is in flight and observe whether the result still gets cached.
actor DescriptionLookupGate {
  private var released = false
  private var lookups = 0
  private var firstLookupWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func recordLookup() {
    lookups += 1
    if lookups == 1 {
      firstLookupWaiters.forEach { $0.resume() }
      firstLookupWaiters.removeAll()
    }
  }

  func waitForFirstLookup() async {
    if lookups >= 1 { return }
    await withCheckedContinuation { firstLookupWaiters.append($0) }
  }

  func waitForRelease() async {
    if released { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func release() {
    released = true
    releaseWaiters.forEach { $0.resume() }
    releaseWaiters.removeAll()
  }

  func lookupCount() -> Int { lookups }
}
