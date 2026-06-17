import Foundation
import Testing

@testable import OpenJoystickDriverKit

private func containsEvent(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

struct DS4ParserTests {
  @Test
  func testWiredIOHIDReportWithoutReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(buttons0: 0x28))

    #expect(containsEvent(events, .buttonPressed(.cross)))
  }
  @Test
  func testRawUSBReportWithReportIDParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report(includesReportID: true))

    let events = try parser.parse(
      data: makeDS4Report(includesReportID: true, buttons0: 0x28)
    )

    #expect(containsEvent(events, .buttonPressed(.cross)))
  }
  @Test
  func testBluetoothReport11ParsesFaceButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport())

    let events = try parser.parse(data: makeDS4BluetoothReport(buttons0: 0x28))

    #expect(containsEvent(events, .buttonPressed(.cross)))
  }
  @Test
  func testBluetoothHIDTransactionReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport(includesHIDTransaction: true))

    let events = try parser.parse(
      data: makeDS4BluetoothReport(
        includesHIDTransaction: true,
        leftStickX: 255,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 255,
        buttons1: 0x30,
        buttons2: 0x03,
        leftTrigger: 255,
        rightTrigger: 128
      )
    )

    #expect(containsEvent(events, .leftStickChanged(x: 127.0 / 128.0, y: 1.0)))
    #expect(containsEvent(events, .rightStickChanged(x: -1.0, y: -127.0 / 128.0)))
    #expect(containsEvent(events, .leftTriggerChanged(1.0)))
    #expect(containsEvent(events, .rightTriggerChanged(128.0 / 255.0)))
    #expect(containsEvent(events, .buttonPressed(.share)))
    #expect(containsEvent(events, .buttonPressed(.options)))
    #expect(containsEvent(events, .buttonPressed(.ps)))
    #expect(containsEvent(events, .buttonPressed(.touchpad)))
  }
  @Test
  func testBluetoothPayloadWithoutReportIDParsesDpad() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4BluetoothReport(includesReportID: false))

    let events = try parser.parse(
      data: makeDS4BluetoothReport(includesReportID: false, buttons0: 0x02)
    )

    #expect(containsEvent(events, .dpadChanged(.east)))
  }
  @Test
  func testBluetoothShortReportWithHIDTransactionParsesFaceButtons() throws {
    let parser = DS4Parser(prefersBluetooth: true)
    _ = try parser.parse(data: Data([0xA1] + Array(makeDS4Report(includesReportID: true))))

    let events = try parser.parse(
      data: Data([0xA1] + Array(makeDS4Report(includesReportID: true, buttons0: 0x28)))
    )

    #expect(containsEvent(events, .buttonPressed(.cross)))
  }
  @Test
  func testObservedMacOSBluetoothReport11ParsesStickState() throws {
    let parser = DS4Parser(prefersBluetooth: true)
    let observedPrefix: [UInt8] = [
      0x11, 0xC0, 0x00, 0x7A, 0x81, 0x81, 0x82, 0x08, 0x00, 0xCC, 0x00, 0x00,
      0xF5, 0xD1, 0x0C, 0xF6, 0xFF, 0x0B, 0x00, 0xF3, 0xFF, 0x78, 0x00, 0x8E,
    ]
    let observedReport = Data(observedPrefix + [UInt8](repeating: 0, count: 54))

    let events = try parser.parse(data: observedReport)

    #expect(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
    #expect(containsEvent(events, .rightStickChanged(x: 0, y: 0)))
    #expect(containsEvent(events, .dpadChanged(.neutral)))
    #expect(!events.contains { event in
      if case .buttonPressed = event { return true }
      return false
    })
  }
  @Test
  func testWiredIOHIDReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(
        leftStickX: 255,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 255,
        buttons1: 0x30,
        buttons2: 0x03,
        leftTrigger: 255,
        rightTrigger: 128
      )
    )

    let expectedLeftStick = ControllerEvent.leftStickChanged(x: 127.0 / 128.0, y: 1.0)
    let expectedRightStick = ControllerEvent.rightStickChanged(x: -1.0, y: -127.0 / 128.0)
    let expectedLeftTrigger = ControllerEvent.leftTriggerChanged(1.0)
    let expectedRightTrigger = ControllerEvent.rightTriggerChanged(128.0 / 255.0)

    #expect(containsEvent(events, expectedLeftStick))
    #expect(containsEvent(events, expectedRightStick))
    #expect(containsEvent(events, expectedLeftTrigger))
    #expect(containsEvent(events, expectedRightTrigger))
    #expect(containsEvent(events, .buttonPressed(.share)))
    #expect(containsEvent(events, .buttonPressed(.options)))
    #expect(containsEvent(events, .buttonPressed(.ps)))
    #expect(containsEvent(events, .buttonPressed(.touchpad)))
  }
  @Test
  func testWiredIOHIDReportParsesDpadDirections() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let upEvents = try parser.parse(data: makeDS4Report(buttons0: 0x00))
    let rightEvents = try parser.parse(data: makeDS4Report(buttons0: 0x02))
    let downEvents = try parser.parse(data: makeDS4Report(buttons0: 0x04))
    let leftEvents = try parser.parse(data: makeDS4Report(buttons0: 0x06))

    #expect(containsEvent(upEvents, .dpadChanged(.north)))
    #expect(containsEvent(rightEvents, .dpadChanged(.east)))
    #expect(containsEvent(downEvents, .dpadChanged(.south)))
    #expect(containsEvent(leftEvents, .dpadChanged(.west)))
  }
  @Test
  func testSmallDS4StickJitterIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 123, leftStickY: 126, rightStickX: 126, rightStickY: 130)
    )

    #expect(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
    #expect(containsEvent(events, .rightStickChanged(x: 0, y: 0)))
  }
  @Test
  func testObservedDS4LeftStickXDriftIsNormalizedToIdle() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(leftStickX: 120))

    #expect(containsEvent(events, .leftStickChanged(x: 0, y: 0)))
  }
  @Test
  func testDs4StickReportsRawHIDNormalizedRange() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(
      data: makeDS4Report(leftStickX: 254, leftStickY: 2, rightStickX: 2, rightStickY: 254)
    )

    let expectedLeftStick = ControllerEvent.leftStickChanged(x: 126.0 / 128.0, y: 126.0 / 128.0)
    let expectedRightStick = ControllerEvent.rightStickChanged(x: -126.0 / 128.0, y: -126.0 / 128.0)

    #expect(containsEvent(events, expectedLeftStick))
    #expect(containsEvent(events, expectedRightStick))
  }
  @Test
  func testObservedDS4RightStickYShortfallRemainsVisible() throws {
    let parser = DS4Parser()
    _ = try parser.parse(data: makeDS4Report())

    let events = try parser.parse(data: makeDS4Report(rightStickY: 8))
    let expectedRightStick = ControllerEvent.rightStickChanged(x: 0, y: 120.0 / 128.0)

    #expect(containsEvent(events, expectedRightStick))
  }
  @Test
  func testDeviceInputStateExposesDS4DpadAsHeldButtons() async throws {
    let dispatcher = NoOpOutputDispatcher()
    let pipeline = DevicePipeline(
      identifier: DeviceIdentifier(vendorID: 1356, productID: 2508),
      transport: .hid(locationID: 1),
      parser: DS4Parser(),
      dispatcher: dispatcher,
      usbContext: nil
    )
    await pipeline.start()
    await pipeline.feedHIDData(makeDS4Report())

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x00))
    #expect(pipeline.inputState().pressedButtons == [Button.dpadUp.rawValue])

    await pipeline.feedHIDData(makeDS4Report(buttons0: 0x03))
    #expect(Set(pipeline.inputState().pressedButtons) == Set([
      Button.dpadRight.rawValue,
      Button.dpadDown.rawValue,
    ]))

    await pipeline.feedHIDData(makeDS4Report())
    #expect(pipeline.inputState().pressedButtons.isEmpty)
  }
  @Test
  func testRegistryMapsDS4V2IdentityToDS4Parser() {
    let registry = ParserRegistry()
    let identifier = DeviceIdentifier(vendorID: 1356, productID: 2508)
    let profile = registry.runtimeProfile(for: identifier)

    #expect(registry.parserName(for: identifier) == "DS4")
    #expect(profile.protocolVariant == .dualShock4)
  }
}
