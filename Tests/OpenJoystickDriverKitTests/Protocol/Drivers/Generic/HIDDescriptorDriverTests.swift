import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDDescriptorDriverTests {
  private let identifier = DeviceIdentifier(vendorID: 65_534, productID: 1)

  private func parse(_ parser: HIDDescriptorDriver, _ element: HIDElementValue) -> ControllerEvent?
  { parser.parse(elementValue: element, receivedAt: MonotonicTimestamp(nanoseconds: 0)) }

  @Test
  func mapsButtonsAndRepeatsUnchangedStates() {
    let parser = HIDDescriptorDriver(identifier: identifier)
    let pressed = value(page: 0x09, usage: 1, minimum: 0, maximum: 1, integer: 1)
    let released = value(page: 0x09, usage: 1, minimum: 0, maximum: 1, integer: 0)

    let first = parse(parser, pressed)
    #expect(first.contains(.press(.faceSouth)))
    #expect(parse(parser, pressed)?.state == first?.state)
    #expect(parse(parser, released)?.state == .neutral)
    #expect(parse(parser, released)?.state == .neutral)
  }

  @Test
  func normalizesAndPairsStandardStickAxes() {
    let parser = HIDDescriptorDriver(identifier: identifier)

    #expect(parse(parser, axis(usage: 0x30, integer: 255)).contains(.leftStick(x: 1, y: 0)))
    #expect(parse(parser, axis(usage: 0x31, integer: 0)).contains(.leftStick(x: 1, y: -1)))
    #expect(parse(parser, axis(usage: 0x33, integer: 0)).contains(.rightStick(x: -1, y: 0)))
    #expect(parse(parser, axis(usage: 0x34, integer: 255)).contains(.rightStick(x: -1, y: 1)))
  }

  /// HID Generic Desktop Y and Ry put the logical minimum away from the user (up), so canonical
  /// Y, which points up, is at its maximum there. The elements carry this descriptor's ranges.
  @Test
  func explicitDescriptorLogicalMinimumYIsUp() {
    // Usage Page (Generic Desktop), Usage (Game Pad), Collection (Application),
    //   Usage (X), Usage (Y), Usage (Rx), Usage (Ry), Logical Minimum (-127),
    //   Logical Maximum (127), Report Size (8), Report Count (4), Input (Data, Var, Abs),
    //   Usage Page (Button), Usage Minimum (1), Usage Maximum (8), Logical Minimum (0),
    //   Logical Maximum (1), Report Size (1), Report Count (8), Input (Data, Var, Abs),
    // End Collection
    let descriptor: [UInt8] = [
      0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x33, 0x09, 0x34, 0x15,
      0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02, 0x05, 0x09, 0x19, 0x01, 0x29, 0x08,
      0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0xC0,
    ]
    let fields = HIDReportDescriptorParser.parse(descriptor: descriptor)?.fields ?? []
    #expect(fields.count == 12)
    let parser = HIDDescriptorDriver(identifier: identifier)
    func stick(_ usage: Int, atLogicalMinimum: Bool) -> ControllerState? {
      guard let field = fields.first(where: { $0.usagePage == 0x01 && $0.usage == usage }) else {
        return nil
      }
      let integer = atLogicalMinimum ? field.logicalMin : field.logicalMax
      return parse(
        parser,
        value(
          page: 0x01,
          usage: UInt32(usage),
          minimum: field.logicalMin,
          maximum: field.logicalMax,
          integer: integer
        )
      )?.state
    }

    #expect(stick(0x31, atLogicalMinimum: true)?.leftStick == StickPosition(x: .center, y: .max))
    #expect(stick(0x31, atLogicalMinimum: false)?.leftStick == StickPosition(x: .center, y: .min))
    #expect(stick(0x34, atLogicalMinimum: true)?.rightStick == StickPosition(x: .center, y: .max))
    #expect(stick(0x34, atLogicalMinimum: false)?.rightStick == StickPosition(x: .center, y: .min))
    #expect(stick(0x30, atLogicalMinimum: false)?.leftStick.x == .max)
  }

  @Test
  func mapsTriggersHatAndIgnoresUnknownUsages() {
    let parser = HIDDescriptorDriver(identifier: identifier)

    #expect(parse(parser, axis(usage: 0x32, integer: 128)).contains(.leftTrigger(Float(128) / 255)))
    #expect(parse(parser, axis(usage: 0x35, integer: 255)).contains(.rightTrigger(1)))
    #expect(
      parse(parser, value(page: 0x01, usage: 0x39, minimum: 0, maximum: 7, integer: 3)).contains(
        .hat(.southEast)
      )
    )
    #expect(
      parse(parser, value(page: 0x01, usage: 0x39, minimum: 0, maximum: 7, integer: 8)).contains(
        .hat(.neutral)
      )
    )
    #expect(parse(parser, axis(usage: 0x36, integer: 128)) == nil)
    #expect(parse(parser, value(page: 0x09, usage: 12, minimum: 0, maximum: 1, integer: 1)) == nil)
  }

  /// SDL's two `0079:0006` gamepad mappings agree on the buttons: 1-4 are Y, B, A, X, 7-8 are
  /// digital L2 and R2, and 9-12 are back, start, and the stick clicks. Z and Rz carry the right
  /// stick.
  @Test
  func dragonRiseUsesItsButtonOrderAndZRzRightStick() {
    let parser = HIDDescriptorDriver(
      identifier: DeviceIdentifier(vendorID: 0x0079, productID: 6),
      quirks: [.dragonRise]
    )
    let buttons: [ControlID] = [
      .faceNorth, .faceEast, .faceSouth, .faceWest, .leftShoulder, .rightShoulder,
      .leftTriggerButton, .rightTriggerButton, .view, .menu, .leftStickClick, .rightStickClick,
    ]
    for (index, control) in buttons.enumerated() {
      let usage = UInt32(index + 1)
      let press = value(page: 0x09, usage: usage, minimum: 0, maximum: 1, integer: 1)
      #expect(parse(parser, press).contains(.press(control)), "\(control)")
      let release = value(page: 0x09, usage: usage, minimum: 0, maximum: 1, integer: 0)
      #expect(parse(parser, release)?.state == .neutral)
    }
    #expect(parse(parser, axis(usage: 0x32, integer: 255)).contains(.rightStick(x: 1, y: 0)))
    #expect(parse(parser, axis(usage: 0x35, integer: 0)).contains(.rightStick(x: 1, y: -1)))
    #expect(parser.capabilities.controls.contains(.leftTriggerButton))
    #expect(!parser.capabilities.controls.contains(.leftTrigger))
  }

  @Test
  func sessionResetReturnsElementStateToNeutral() {
    let parser = HIDDescriptorDriver(identifier: identifier)
    #expect(parse(parser, axis(usage: 0x30, integer: 255)).contains(.leftStick(x: 1, y: 0)))
    #expect(
      parse(parser, value(page: 0x09, usage: 1, minimum: 0, maximum: 1, integer: 1)).contains(
        .press(.faceSouth)
      )
    )

    parser.resetProtocolState()

    let next = parse(parser, value(page: 0x09, usage: 2, minimum: 0, maximum: 1, integer: 0))
    #expect(next?.state == .neutral)
  }

  @Test
  func rawReportsRemainUnusedForDescriptorDrivenFallback() throws {
    let parser = HIDDescriptorDriver(identifier: identifier)
    #expect(try parser.parseReport(Data([1, 2, 3])) == nil)
  }

  private func axis(usage: UInt32, integer: Int) -> HIDElementValue {
    value(page: 0x01, usage: usage, minimum: 0, maximum: 255, integer: integer)
  }

  private func value(
    page: UInt32,
    usage: UInt32,
    minimum: Int,
    maximum: Int,
    integer: Int
  ) -> HIDElementValue {
    HIDElementValue(
      usagePage: page,
      usage: usage,
      logicalMinimum: minimum,
      logicalMaximum: maximum,
      integerValue: integer
    )
  }
}
