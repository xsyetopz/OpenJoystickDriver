import Foundation
import OpenJoystickDriverKit
import Testing

@Suite("App-owned Compatibility output bridge")
struct AppOwnedCompatibilityOutputBridgeTests {
  @Test func mirrorsDaemonInputStateThroughAppOwnedDispatcher() async throws {
    let dispatcher = RecordingCompatibilityDispatcher()
    let bridge = AppOwnedCompatibilityOutputBridge { identity in
      #expect(identity == .x360HID)
      return dispatcher
    }
    let identifier = DeviceIdentifier(vendorID: 0x046D, productID: 0xC21D)
    let state: DeviceInputState = {
      var state = DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.pressedButtons = [Button.a.rawValue]
      state.leftStickX = 0.5
      return state
    }()

    await bridge.update(isEnabled: true, identity: .x360HID, devices: [identifier]) { _ in state }

    let events = dispatcher.events(for: identifier)
    #expect(events.contains(.buttonPressed(.a)))
    #expect(events.contains(.leftStickChanged(x: 0.5, y: 0)))
  }

  @Test func neutralizesRemovedDevices() async throws {
    let dispatcher = RecordingCompatibilityDispatcher()
    let bridge = AppOwnedCompatibilityOutputBridge { _ in dispatcher }
    let identifier = DeviceIdentifier(vendorID: 0x046D, productID: 0xC21D)
    let state: DeviceInputState = {
      var state = DeviceInputState(vendorID: identifier.vendorID, productID: identifier.productID)
      state.pressedButtons = [Button.a.rawValue]
      return state
    }()

    await bridge.update(isEnabled: true, identity: .sdl2_3, devices: [identifier]) { _ in state }
    await bridge.update(isEnabled: true, identity: .sdl2_3, devices: []) { _ in nil }

    let events = dispatcher.events(for: identifier)
    #expect(events.contains(.buttonReleased(.a)))
  }
}

private final class RecordingCompatibilityDispatcher: CompatibilityUserSpaceOutputDispatching,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var recorded: [DeviceIdentifier: [ControllerEvent]] = [:]

  var suppressOutput = false
  let status = "on"
  let lastRumbleStatus = "none"

  func close() {}

  // swiftlint:disable:next async_without_await
  func dispatch(events: [ControllerEvent], from identifier: DeviceIdentifier) async {
    lock.withLock {
      recorded[identifier, default: []].append(contentsOf: events)
    }
  }

  func events(for identifier: DeviceIdentifier) -> [ControllerEvent] {
    lock.withLock { recorded[identifier] ?? [] }
  }
}
