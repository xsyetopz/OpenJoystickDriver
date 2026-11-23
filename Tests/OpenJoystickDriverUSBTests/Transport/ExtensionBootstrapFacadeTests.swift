import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct ExtensionBootstrapFacadeTests {
  @Test
  func configurationPublishesOnlyTheExtensionRoute() async throws {
    let physical = device()
    let extensionDevice = device(route: .usbExtension, id: 2)
    let extensionProvider = BootstrapExtensionProvider()
    let calls = BootstrapCalls()
    let direct = FakeUSBTransportProvider(devicesResult: .success([physical]))
    let facade = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: direct,
      usbDriverKitProvider: extensionProvider,
      supportedRawUSBModels: [ControllerModelID(physical)],
      requiredDriverKitModels: [ControllerModelID(physical)],
      extensionBootstrap: .init { value in
        await calls.record(value)
        await extensionProvider.publish(extensionDevice)
        return true
      }
    )
    #expect(try await facade.devices() == [extensionDevice])
    #expect(try await facade.devices() == [extensionDevice])
    #expect(await calls.devices == [physical])
    #expect(await direct.openCount == 0)
  }

  @Test
  func supportedAndExtensionOwnedAreBothRequired() async throws {
    let physical = device()
    let thirdParty = device(id: 3, vendor: 0x3537, product: 0x1010)
    let calls = BootstrapCalls()
    let facade = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(devicesResult: .success([physical, thirdParty])),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [ControllerModelID(thirdParty)],
      requiredDriverKitModels: [ControllerModelID(physical)],
      extensionBootstrap: .init { value in
        await calls.record(value)
        return true
      }
    )
    #expect(try await facade.devices() == [thirdParty])
    #expect(await calls.devices.isEmpty)
  }

  @Test
  func failedExtensionDiscoveryIsNotTreatedAsAbsence() async throws {
    let physical = device()
    let calls = BootstrapCalls()
    let facade = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(devicesResult: .success([physical])),
      usbDriverKitProvider: FakeUSBTransportProvider(devicesResult: .failure(.accessDenied)),
      supportedRawUSBModels: [ControllerModelID(physical)],
      requiredDriverKitModels: [ControllerModelID(physical)],
      extensionBootstrap: .init { value in
        await calls.record(value)
        return true
      }
    )
    #expect(try await facade.devices().isEmpty)
    #expect(await calls.devices.isEmpty)
  }

  @Test
  func aFailedAttemptIsRateLimitedWithoutHidingOtherDevices() async throws {
    let physical = device()
    let thirdParty = device(id: 3, vendor: 0x3537, product: 0x1010)
    let calls = BootstrapCalls()
    let clock = BootstrapClock()
    let facade = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(devicesResult: .success([physical, thirdParty])),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [ControllerModelID(physical), ControllerModelID(thirdParty)],
      requiredDriverKitModels: [ControllerModelID(physical)],
      extensionBootstrap: .init(
        clock: { clock.read() },
        prepare: { value in
          await calls.record(value)
          throw USBTransportError.accessDenied
        }
      )
    )
    #expect(try await facade.devices() == [thirdParty])
    #expect(try await facade.devices() == [thirdParty])
    #expect(await calls.devices.count == 1)
    clock.advance()
    #expect(try await facade.devices() == [thirdParty])
    #expect(await calls.devices.count == 2)
  }

  @Test
  func concurrentPollDoesNotDuplicateAnInFlightBootstrap() async throws {
    let physical = device()
    let calls = BootstrapCalls()
    let gate = BootstrapGate()
    let facade = OpenJoystickDriverUSBTransportProvider(
      ioUSBHostProvider: FakeUSBTransportProvider(devicesResult: .success([physical])),
      usbDriverKitProvider: FakeUSBTransportProvider(),
      supportedRawUSBModels: [ControllerModelID(physical)],
      requiredDriverKitModels: [ControllerModelID(physical)],
      extensionBootstrap: .init(
        clock: { 0 },
        prepare: { value in
          let attempt = await calls.record(value)
          if attempt == 1 { await gate.wait() }
          return false
        }
      )
    )
    let first = Task { try await facade.devices() }
    while await calls.devices.isEmpty {
      try Task.checkCancellation()
      await Task.yield()
    }
    #expect(try await facade.devices().isEmpty)
    #expect(await calls.devices.count == 1)
    await gate.release()
    #expect(try await first.value.isEmpty)
  }

  private func device(
    route: USBTransportRoute = .rawUSB,
    id: UInt64 = 1,
    vendor: UInt16 = 0x045E,
    product: UInt16 = 0x02D1
  ) -> USBTransportDevice {
    USBTransportDevice(
      route: route,
      serviceID: id,
      vendorID: vendor,
      productID: product,
      locationID: 1
    )
  }
}

private actor BootstrapCalls {
  private(set) var devices: [USBTransportDevice] = []
  @discardableResult
  func record(_ device: USBTransportDevice) -> Int {
    devices.append(device)
    return devices.count
  }
}

private actor BootstrapGate {
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func wait() async {
    guard !released else { return }
    await withCheckedContinuation { continuation = $0 }
  }
  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}

private actor BootstrapExtensionProvider: USBTransportProvider {
  private var listed: [USBTransportDevice] = []
  func devices() -> [USBTransportDevice] { listed }
  func publish(_ device: USBTransportDevice) { listed = [device] }
  func open(
    _: USBTransportDevice,
    options _: USBTransportOpenOptions
  ) throws
    -> any USBTransportSession
  { throw USBTransportError.notSupported }
}

/// The lock protects the injected clock across Sendable closures.
private final class BootstrapClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: TimeInterval = 0
  func read() -> TimeInterval { lock.withLock { value } }
  func advance() { lock.withLock { value += 3 } }
}
