import Foundation
import OpenJoystickDriverKit
import Testing

struct GenericHIDParserTests {
  private let identifier = DeviceIdentifier(vendorID: 65_534, productID: 1)

  @Test
  func mapsButtonsAndSuppressesDuplicateStates() {
    let parser = GenericHIDParser(identifier: identifier)
    let pressed = value(page: 0x09, usage: 1, minimum: 0, maximum: 1, integer: 1)
    let released = value(page: 0x09, usage: 1, minimum: 0, maximum: 1, integer: 0)

    #expect(parser.parse(elementValue: pressed) == [.buttonPressed(.a)])
    #expect(parser.parse(elementValue: pressed).isEmpty)
    #expect(parser.parse(elementValue: released) == [.buttonReleased(.a)])
    #expect(parser.parse(elementValue: released).isEmpty)
  }

  @Test
  func normalizesAndPairsStandardStickAxes() {
    let parser = GenericHIDParser(identifier: identifier)

    #expect(parser.parse(elementValue: axis(usage: 0x30, integer: 255)) == [
      .leftStickChanged(x: 1, y: 0),
    ])
    #expect(parser.parse(elementValue: axis(usage: 0x31, integer: 0)) == [
      .leftStickChanged(x: 1, y: 1),
    ])
    #expect(parser.parse(elementValue: axis(usage: 0x33, integer: 0)) == [
      .rightStickChanged(x: -1, y: 0),
    ])
    #expect(parser.parse(elementValue: axis(usage: 0x34, integer: 255)) == [
      .rightStickChanged(x: -1, y: -1),
    ])
  }

  @Test
  func mapsTriggersHatAndIgnoresUnknownUsages() {
    let parser = GenericHIDParser(identifier: identifier)

    #expect(parser.parse(elementValue: axis(usage: 0x32, integer: 128)) == [
      .leftTriggerChanged(Float(128) / 255),
    ])
    #expect(parser.parse(elementValue: axis(usage: 0x35, integer: 255)) == [
      .rightTriggerChanged(1),
    ])
    #expect(parser.parse(elementValue: value(
      page: 0x01,
      usage: 0x39,
      minimum: 0,
      maximum: 7,
      integer: 3
    )) == [.dpadChanged(.southEast)])
    #expect(parser.parse(elementValue: value(
      page: 0x01,
      usage: 0x39,
      minimum: 0,
      maximum: 7,
      integer: 8
    )) == [.dpadChanged(.neutral)])
    #expect(parser.parse(elementValue: axis(usage: 0x36, integer: 128)).isEmpty)
  }

  @Test
  func rawReportsRemainUnusedForDescriptorDrivenFallback() throws {
    let parser = GenericHIDParser(identifier: identifier)
    #expect(try parser.parse(data: Data([1, 2, 3])).isEmpty)
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
