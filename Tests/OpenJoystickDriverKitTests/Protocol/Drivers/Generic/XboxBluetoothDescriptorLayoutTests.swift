import Foundation
import OpenJoystickDriverKit
import Testing

/// Xbox One S and Series pads over Bluetooth, mapped from their recorded report descriptors
/// (``RecordedHIDDescriptors``). Linux mode puts the right stick on Z/Rz and the triggers on
/// Simulation Brake and Accelerator (10-bit), View on Consumer AC Back (One S) and Share on
/// Consumer Record (Series), and Guide on Consumer AC Home in report 2. Windows mode puts the
/// right stick on Rx/Ry, the triggers on Z/Rz, and Guide on System Main Menu in report 2.
struct XboxBluetoothDescriptorLayoutTests {
  private static let xboxOneS = DeviceIdentifier(vendorID: 0x045E, productID: 0x02FD)
  private static let xboxSeries = DeviceIdentifier(vendorID: 0x045E, productID: 0x0B13)

  @Test(arguments: [
    RecordedHIDDescriptors.xboxOneSLinux, RecordedHIDDescriptors.xboxOneSWindows,
    RecordedHIDDescriptors.xboxSeries, RecordedHIDDescriptors.gameSirG7SE,
  ])
  func recordedDescriptorsSatisfyTheContract(descriptor: Data) {
    #expect(
      HIDDescriptorContract.violation(in: HIDLayoutSummary(reportDescriptor: descriptor)) == nil
    )
  }

  @Test
  func oneSLinuxModeMapsZRzStickAndSimulationTriggers() {
    let parser = HIDDescriptorDriver(
      identifier: Self.xboxOneS,
      reportDescriptor: RecordedHIDDescriptors.xboxOneSLinux
    )
    #expect(parse(parser, axis(usage: 0x32, integer: 65535)).contains(.rightStick(x: 1, y: 0)))
    #expect(parse(parser, axis(usage: 0x35, integer: 65535)).contains(.rightStick(x: 1, y: 1)))
    #expect(parse(parser, trigger(page: 2, usage: 0xC5, integer: 1023)).contains(.leftTrigger(1)))
    #expect(parse(parser, trigger(page: 2, usage: 0xC4, integer: 1023)).contains(.rightTrigger(1)))
    #expect(!parser.capabilities.controls.contains(.share))
  }

  @Test
  func oneSLinuxModeMapsConsumerViewAndGuide() {
    let parser = HIDDescriptorDriver(
      identifier: Self.xboxOneS,
      reportDescriptor: RecordedHIDDescriptors.xboxOneSLinux
    )
    #expect(parse(parser, button(page: 0x0C, usage: 0x224, reportID: 1)).contains(.press(.view)))
    #expect(parse(parser, button(page: 0x0C, usage: 0x223, reportID: 2)).contains(.press(.guide)))
    #expect(parse(parser, button(usage: 12, reportID: 1)).contains(.press(.menu)))
    #expect(parse(parser, button(usage: 5, reportID: 1)).contains(.press(.faceNorth)))
  }

  @Test
  func seriesMapsRecordAsShareAndButton13AsGuide() {
    let parser = HIDDescriptorDriver(
      identifier: Self.xboxSeries,
      reportDescriptor: RecordedHIDDescriptors.xboxSeries
    )
    #expect(parser.capabilities.controls.contains(.share))
    #expect(parse(parser, button(page: 0x0C, usage: 0xB2, reportID: 1)).contains(.press(.share)))
    #expect(parse(parser, button(usage: 13, reportID: 1)).contains(.press(.guide)))
    #expect(parse(parser, button(usage: 11, reportID: 1)).contains(.press(.view)))
  }

  @Test
  func oneSWindowsModeMapsRxRyStickZRzTriggersAndSystemMainMenuGuide() {
    let parser = HIDDescriptorDriver(
      identifier: Self.xboxOneS,
      reportDescriptor: RecordedHIDDescriptors.xboxOneSWindows
    )
    #expect(parse(parser, axis(usage: 0x33, integer: 65535)).contains(.rightStick(x: 1, y: 0)))
    #expect(parse(parser, trigger(page: 1, usage: 0x32, integer: 1023)).contains(.leftTrigger(1)))
    #expect(parse(parser, trigger(page: 1, usage: 0x35, integer: 1023)).contains(.rightTrigger(1)))
    let buttons: [ControlID] = [
      .faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .view, .menu,
      .leftStickClick, .rightStickClick,
    ]
    for (index, control) in buttons.enumerated() {
      #expect(
        parse(parser, button(usage: UInt32(index + 1), reportID: 1)).contains(.press(control))
      )
    }
    #expect(parse(parser, button(page: 1, usage: 0x85, reportID: 2)).contains(.press(.guide)))
  }

  private func parse(
    _ parser: HIDDescriptorDriver,
    _ elementValue: HIDElementValue
  ) -> ControllerEvent? {
    parser.parse(elementValue: elementValue, receivedAt: MonotonicTimestamp(nanoseconds: 0))
  }

  private func axis(usage: UInt32, integer: Int) -> HIDElementValue {
    HIDElementValue(
      usagePage: 1,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: 65535,
      integerValue: integer,
      reportID: 1
    )
  }

  private func trigger(page: UInt32, usage: UInt32, integer: Int) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: 1023,
      integerValue: integer,
      reportID: 1
    )
  }

  private func button(page: UInt32 = 9, usage: UInt32, reportID: UInt32) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: 0,
      logicalMaximum: 1,
      integerValue: 1,
      reportID: reportID
    )
  }
}
