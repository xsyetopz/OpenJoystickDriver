import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension DualShock4DriverTests {
  @Test
  func testValidatedReportsExposeAbsoluteControlsAndAdvancingTimestamp() throws {
    let parser = DualShock4Driver()

    let first = try parser.parseReport(
      makeDS4Report(rightStickX: 255, buttons0: 0x28, sensorTimestamp: 0xFFFF)
    )
    #expect(first?.isFresh == true)
    #expect(first.contains(.rightStick(x: 127.0 / 128.0, y: 0)))
    #expect(first.contains(.press(.south)))

    #expect(try parser.parseReport(makeDS4Report(sensorTimestamp: 0xFFFF))?.isFresh == false)
    #expect(try parser.parseReport(makeDS4Report(sensorTimestamp: 0))?.isFresh == true)
    #expect(try parser.parseReport(makeDS4Report(sensorTimestamp: 0xFFFF))?.isFresh == false)
  }

  @Test
  func testInvalidBluetoothReportLeavesLastValidState() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)
    _ = try parser.parseReport(makeDS4BluetoothReport(buttons0: 0x28, sensorTimestamp: 1))
    var invalidReport = Array(makeDS4BluetoothReport(sensorTimestamp: 2))
    invalidReport[20] ^= 1

    #expect(throws: DualShock4DriverError.invalidBluetoothCRC) {
      try parser.parseReport(Data(invalidReport))
    }
    // The throw kept the held button and the sensor clock of the last valid report.
    let next = try parser.parseReport(makeDS4BluetoothReport(buttons0: 0x28, sensorTimestamp: 2))
    #expect(next.contains(.press(.south)))
    #expect(next?.isFresh == true)
  }

  @Test
  func testUSBReportsBatteryBucketsAndWiredPower() throws {
    let parser = DualShock4Driver()

    _ = try parser.parseReport(makeDS4Report(includesReportID: true, status: 0x00))
    #expect(parser.power == ds4Power(.discharging, 0...9, wired: false))

    _ = try parser.parseReport(makeDS4Report(includesReportID: true, status: 0x13))
    #expect(parser.power == ds4Power(.charging, 30...39, wired: true))

    _ = try parser.parseReport(makeDS4Report(includesReportID: true, status: 0x1B))
    #expect(parser.power == ds4Power(.full, 100...100, wired: true))
  }

  @Test(arguments: Array(UInt8(0)...UInt8(9)))
  func testEveryBatteryBucketPreservesItsReportedRange(_ level: UInt8) throws {
    let parser = DualShock4Driver()

    _ = try parser.parseReport(makeDS4Report(status: level))

    #expect(parser.power?.battery.percentage == level * 10...(level * 10 + 9))
    #expect(parser.power?.battery.percentageText == "\(level * 10)-\(level * 10 + 9)%")
  }

  @Test
  func testBluetoothReportParsesPower() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)

    _ = try parser.parseReport(makeDS4BluetoothReport(status: 0x1A))

    #expect(parser.power == ds4Power(.charging, 100...100, wired: true))
  }

  @Test
  func testLevelTenRetainsObservedWiredPower() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report(status: 0x0A))
    #expect(parser.power == ds4Power(.discharging, 100...100, wired: false))

    _ = try parser.parseReport(makeDS4Report(status: 0x1A))
    #expect(parser.power == ds4Power(.charging, 100...100, wired: true))
  }

  @Test
  func testInvalidAndMinimalBatteryLevelsRemainUnknown() throws {
    let wired = DualShock4Driver()
    _ = try wired.parseReport(makeDS4Report(status: 0x0F))
    #expect(wired.power == ds4Power(.unknown, nil, wired: false))

    _ = try wired.parseReport(makeDS4Report(status: 0x1E))
    #expect(wired.power == ds4Power(.unknown, nil, wired: true))

    let minimal = DualShock4Driver(prefersBluetooth: true)
    _ = try minimal.parseReport(Data([0x01, 128, 128, 128, 128, 0x08, 0, 0, 0, 0]))
    #expect(minimal.power == nil)
  }

  func ds4Power(
    _ charging: ControllerConnectionState.Charging,
    _ percentage: ClosedRange<UInt8>?,
    wired: Bool
  ) -> ControllerConnectionState.Power {
    ControllerConnectionState.Power(
      charging: charging,
      battery: BatteryLevel(percentage: percentage),
      wiredPower: wired
    )
  }

  @Test
  func testWiredReportWithoutReportIDIsRejected() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    #expect(throws: DualShock4DriverError.invalidReportFraming) {
      try parser.parseReport(makeDS4Report(includesReportID: false, buttons0: 0x28))
    }
  }

  @Test
  func testUSBFaceButtonTransitionsRemainOrderedAcrossUnrelatedInput() throws {
    try assertFaceButtonContinuity { buttons, leftStickX, rightStickX in
      makeDS4Report(
        includesReportID: true,
        leftStickX: leftStickX,
        rightStickX: rightStickX,
        buttons0: buttons
      )
    }
  }

  @Test
  func testBluetoothFaceButtonTransitionsRemainOrderedAcrossUnrelatedInput() throws {
    try assertFaceButtonContinuity { buttons, leftStickX, rightStickX in
      makeDS4BluetoothReport(leftStickX: leftStickX, rightStickX: rightStickX, buttons0: buttons)
    }
  }

  @Test
  func testBluetoothHIDTransactionReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4BluetoothReport(includesHIDTransaction: true))

    let events = try parser.parseReport(
      makeDS4BluetoothReport(
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

    #expect(events.contains(.leftStick(x: 127.0 / 128.0, y: -1.0)))
    #expect(events.contains(.rightStick(x: -1.0, y: 127.0 / 128.0)))
    #expect(events.contains(.leftTrigger(1.0)))

    #expect(events.contains(.rightTrigger(128.0 / 255.0)))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.touchpadClick)))
  }

  @Test
  func testBluetoothPayloadWithoutReportIDIsRejected() throws {

    let parser = DualShock4Driver()
    #expect(throws: DualShock4DriverError.invalidReportFraming) {
      try parser.parseReport(makeDS4BluetoothReport(includesReportID: false))
    }
  }

  @Test
  func testBluetoothShortReportWithHIDTransactionParsesFaceButtons() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)
    let neutral: [UInt8] = [0xA1, 0x01, 128, 128, 128, 128, 0x08, 0, 0, 0, 0]
    _ = try parser.parseReport(Data(neutral))

    var pressed = neutral
    pressed[6] = 0x28
    let events = try parser.parseReport(Data(pressed))

    #expect(events.contains(.press(.south)))
  }

  @Test
  func testCompleteBluetoothReportRejectsInvalidCRC() throws {
    let parser = DualShock4Driver(prefersBluetooth: true)
    let observedPrefix: [UInt8] = [
      0x11, 0xC0, 0x00, 0x7A, 0x81, 0x81, 0x82, 0x08, 0x00, 0xCC, 0x00, 0x00, 0xF5, 0xD1, 0x0C,
      0xF6, 0xFF, 0x0B, 0x00, 0xF3, 0xFF, 0x78, 0x00, 0x8E,
    ]
    let observedReport = Data(observedPrefix + [UInt8](repeating: 0, count: 54))

    #expect(throws: DualShock4DriverError.invalidBluetoothCRC) {
      try parser.parseReport(observedReport)
    }
  }

  @Test
  func testWiredIOHIDReportParsesSticksTriggersAndSystemButtons() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let events = try parser.parseReport(
      makeDS4Report(
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

    let expectedLeftStick = InputChange.leftStick(x: 127.0 / 128.0, y: -1.0)
    let expectedRightStick = InputChange.rightStick(x: -1.0, y: 127.0 / 128.0)
    let expectedLeftTrigger = InputChange.leftTrigger(1.0)
    let expectedRightTrigger = InputChange.rightTrigger(128.0 / 255.0)

    #expect(events.contains(expectedLeftStick))
    #expect(events.contains(expectedRightStick))
    #expect(events.contains(expectedLeftTrigger))
    #expect(events.contains(expectedRightTrigger))
    #expect(events.contains(.press(.back)))
    #expect(events.contains(.press(.start)))
    #expect(events.contains(.press(.guide)))
    #expect(events.contains(.press(.touchpadClick)))
  }

  @Test
  func testWiredIOHIDReportParsesDpadDirections() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let upEvents = try parser.parseReport(makeDS4Report(buttons0: 0x00))
    let rightEvents = try parser.parseReport(makeDS4Report(buttons0: 0x02))
    let downEvents = try parser.parseReport(makeDS4Report(buttons0: 0x04))
    let leftEvents = try parser.parseReport(makeDS4Report(buttons0: 0x06))

    #expect(upEvents.contains(.hat(.north)))
    #expect(rightEvents.contains(.hat(.east)))
    #expect(downEvents.contains(.hat(.south)))
    #expect(leftEvents.contains(.hat(.west)))
  }

  @Test
  func testSmallDS4StickJitterPassesThroughWithoutDriverDeadzone() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let events = try parser.parseReport(
      makeDS4Report(leftStickX: 123, leftStickY: 126, rightStickX: 126, rightStickY: 130)
    )

    #expect(events.contains(.leftStick(x: -5.0 / 128, y: -2.0 / 128)))
    #expect(events.contains(.rightStick(x: -2.0 / 128, y: 2.0 / 128)))
  }

  private func assertFaceButtonContinuity(makeReport: (UInt8, UInt8, UInt8) -> Data) throws {
    let faceButtons: [(mask: UInt8, button: Control)] = [
      (0x10, .west), (0x20, .south), (0x40, .east), (0x80, .north),
    ]

    for faceButton in faceButtons {
      let parser = DualShock4Driver()
      _ = try parser.parseReport(makeReport(0x08, 128, 128))

      let pressed = try parser.parseReport(makeReport(0x08 | faceButton.mask, 128, 128))
      let held = try parser.parseReport(makeReport(0x08 | faceButton.mask, 255, 128))
      let released = try parser.parseReport(makeReport(0x08, 255, 128))
      let laterInput = try parser.parseReport(makeReport(0x08, 255, 0))

      #expect(pressed.contains(.press(faceButton.button)))
      #expect(held.contains(.press(faceButton.button)))
      #expect(held.contains(.leftStick(x: 127.0 / 128.0, y: 0)))
      #expect(released.contains(.release(faceButton.button)))
      #expect(laterInput.contains(.release(faceButton.button)))
      #expect(laterInput.contains(.rightStick(x: -1, y: 0)))
    }
  }

  @Test
  func testObservedDS4LeftStickXDriftPassesThroughWithoutDriverDeadzone() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let events = try parser.parseReport(makeDS4Report(leftStickX: 120))

    #expect(events.contains(.leftStick(x: -8.0 / 128, y: 0)))
  }

  @Test
  func testDs4StickReportsRawHIDNormalizedRange() throws {
    let parser = DualShock4Driver()
    _ = try parser.parseReport(makeDS4Report())

    let events = try parser.parseReport(
      makeDS4Report(leftStickX: 254, leftStickY: 2, rightStickX: 2, rightStickY: 254)
    )

    let expectedLeftStick = InputChange.leftStick(x: 126.0 / 128.0, y: -126.0 / 128.0)
    let expectedRightStick = InputChange.rightStick(x: -126.0 / 128.0, y: 126.0 / 128.0)

    #expect(events.contains(expectedLeftStick))
    #expect(events.contains(expectedRightStick))
  }

  @Test
  func testBothStickYAxesReportUpCenterAndDown() throws {
    let parser = DualShock4Driver()

    let up = try parser.parseReport(makeDS4Report(leftStickY: 0, rightStickY: 0))
    let center = try parser.parseReport(makeDS4Report(leftStickY: 128, rightStickY: 128))
    let down = try parser.parseReport(makeDS4Report(leftStickY: 255, rightStickY: 255))

    #expect(up.contains(.leftStick(x: 0, y: -1)))
    #expect(up.contains(.rightStick(x: 0, y: -1)))
    #expect(center.contains(.leftStick(x: 0, y: 0)))
    #expect(center.contains(.rightStick(x: 0, y: 0)))
    #expect(down.contains(.leftStick(x: 0, y: 127.0 / 128.0)))
    #expect(down.contains(.rightStick(x: 0, y: 127.0 / 128.0)))
  }
}
