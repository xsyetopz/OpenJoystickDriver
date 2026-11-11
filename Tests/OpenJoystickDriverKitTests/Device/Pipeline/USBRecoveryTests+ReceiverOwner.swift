import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

extension USBPipelineRecoveryTests {
  @Test
  func receiverHeldByAnotherClientIsNamedWritesNothingAndOpensOnRelease() async throws {
    let registry = ProtocolDriverRegistry()
    let classification = registry.classify(
      PhysicalDevice(vendorID: 0x045E, productID: 0x0719),
      backend: .rawUSB
    )
    guard case .bound(let binding) = classification else {
      Issue.record("did not bind: \(classification)")
      return
    }
    let claim = USBTransportResolution(
      profile: try #require(registry.runtimeProfile(for: binding)).transportProfile
    )
    let driver = try registry.makeDriver(
      for: binding,
      model: ControllerModelID(vendorID: 0x045E, productID: 0x0719),
      claimed: claim,
      slotOrdinal: 0
    ).get()
    let receiver = USBTransportDevice(
      route: .rawUSB,
      serviceID: 2,
      vendorID: 0x045E,
      productID: 0x0719,
      locationID: 8
    )
    let session = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [session])
    await provider.failNextOpens(with: [.ownedByAnotherClient(owner: "pid 11070, steam_osx")])
    let dispatcher = RecoveryOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(
        vendorID: 0x045E,
        productID: 0x0719,
        locationID: 8,
        interfaceNumber: 0
      ),
      transport: .usb(device: receiver),
      driver: driver,
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 1_000_000,
        reconnectMaximumDelayNanoseconds: 1_000_000,
        accessContentionDelayNanoseconds: 1_000_000
      )
    )

    let start = Task { await pipeline.start() }
    await waitUntil("the release wait begins") { await provider.releaseWaitCount == 1 }
    #expect(dispatcher.ownershipReports.contains(.ownedByAnotherClient))
    #expect(await pipeline.usbExclusiveOwner?.name == "steam_osx")
    #expect(await session.writeCount == 0)
    // A timed retry would reopen within these milliseconds despite the held state.
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(await provider.openCount == 1)

    await provider.announceRelease()
    await waitUntil("the interface is opened again") { await provider.openCount == 2 }
    await waitUntil("the hold clears") { await !pipeline.usbOwnedByAnotherClient }

    await pipeline.stop()
    await start.value
  }
}
