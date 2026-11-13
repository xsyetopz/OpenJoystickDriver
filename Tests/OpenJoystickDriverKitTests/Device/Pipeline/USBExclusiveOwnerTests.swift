import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct USBExclusiveOwnerTests {
  @Test
  func userSpaceOwnerCarriesItsProcessIDAndName() {
    #expect(
      USBExclusiveOwner(registryValue: "pid 11070, steam_osx")
        == USBExclusiveOwner(processID: 11070, name: "steam_osx")
    )
  }

  @Test
  func kernelDriverOwnerCarriesOnlyItsName() {
    #expect(
      USBExclusiveOwner(registryValue: "AppleUSB20Hub")
        == USBExclusiveOwner(processID: nil, name: "AppleUSB20Hub")
    )
    #expect(
      USBExclusiveOwner(registryValue: "pid x, broken")
        == USBExclusiveOwner(processID: nil, name: "pid x, broken")
    )
  }

  @Test
  func emptyValueNamesNoOwner() {
    #expect(USBExclusiveOwner(registryValue: "  ") == nil)
  }

  @Test
  func heldMessageNamesOwnerOrSaysThereIsNone() {
    let catalog = [
      "status.controllerOwner.named": "%1$@ pid %2$@",
      "status.controllerOwner.nameOnly": "name %@",
      "status.controllerOwner.unnamed": "unnamed",
    ]
    func message(_ owner: USBExclusiveOwner?) -> String {
      USBExclusiveOwner.heldMessage(for: owner) { catalog[$0] ?? $0 }
    }
    #expect(message(USBExclusiveOwner(processID: 7, name: "steam_osx")) == "steam_osx pid 7")
    #expect(
      message(USBExclusiveOwner(processID: nil, name: "AppleUSB20Hub")) == "name AppleUSB20Hub"
    )
    #expect(message(nil) == "unnamed")
  }
}

struct USBExclusiveOwnerRecoveryTests {
  let identifier = LogicalControllerID(
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 7,
    interfaceNumber: 0
  )
  let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 1,
    vendorID: 0x3537,
    productID: 0x1010,
    locationID: 7
  )

  @Test
  func releaseEventReopensInterfaceWithoutPolling() async {
    let owner = "pid 11070, steam_osx"
    let session = RecoveryUSBSession(readError: .timeout)
    let provider = RecoveryUSBProvider(sessions: [session])
    await provider.failNextOpens(with: [.ownedByAnotherClient(owner: owner)])
    let dispatcher = RecoveryOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      driver: RecoveryInputParser(),
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      usbRecoveryPolicy: USBPipelineRecoveryPolicy(
        openRetryDelays: [1],
        reconnectBaseDelayNanoseconds: 60_000_000_000,
        reconnectMaximumDelayNanoseconds: 60_000_000_000,
        accessContentionDelayNanoseconds: 60_000_000_000
      )
    )

    let start = Task { await pipeline.start() }
    await waitUntil("the release wait begins") { await provider.releaseWaitCount == 1 }
    #expect(dispatcher.ownershipReports.contains(.ownedByAnotherClient))
    #expect(await pipeline.usbOwnedByAnotherClient)
    #expect(await pipeline.usbExclusiveOwner == USBExclusiveOwner(registryValue: owner))
    #expect(await provider.openCount == 1)

    await provider.announceRelease()
    await waitUntil("the interface is opened again") { await provider.openCount == 2 }
    await waitUntil("the hold clears") { await !pipeline.usbOwnedByAnotherClient }
    #expect(await pipeline.usbExclusiveOwner == nil)

    await pipeline.stop()
    await start.value
    #expect(await session.closeCount == 1)
  }
}
