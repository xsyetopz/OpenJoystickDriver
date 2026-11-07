import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The SteelSeries Nimbus `1038:1420` record, from its descriptor layout and SDL's mapping.
///
/// No capture of the pad backs these tests; the descriptor below is written from the layout the
/// task brief gives: four D-pad pressure bytes, eight button pressure bytes, one Consumer AC Home
/// bit and four signed stick bytes. The record's Menu, threshold and axis signs wait for the
/// hardware checks in `openspec/changes/steelseries-nimbus/tasks.md`.
struct SteelSeriesNimbusTests {
  private static let model = ControllerModelID(vendorID: 0x1038, productID: 0x1420)

  /// Generic Desktop D-pad usages 0x90 to 0x93 and buttons 1 to 8, one byte each, then the
  /// Consumer AC Home bit, then X, Y, Z and Rz as signed bytes.
  private static let descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01,
    0x09, 0x90, 0x09, 0x92, 0x09, 0x91, 0x09, 0x93,
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x08,
    0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x08, 0x81, 0x02,
    0x05, 0x0C, 0x0A, 0x23, 0x02, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02,
    0x75, 0x07, 0x95, 0x01, 0x81, 0x03,
    0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x32, 0x09, 0x35,
    0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x04, 0x81, 0x02,
    0xC0,
  ]

  private func driver() throws -> HIDDescriptorDriver {
    HIDDescriptorDriver(
      model: Self.model,
      reportDescriptor: Data(Self.descriptor),
      usageMap: try catalogUsageMap(0x1038, 0x1420)
    )
  }

  private func parse(
    _ driver: HIDDescriptorDriver,
    page: UInt32,
    usage: UInt32,
    _ integer: Int,
    range: ClosedRange<Int> = 0...255
  ) -> ControllerEvent? {
    driver.parse(
      elementValue: HIDElementValue(
        usagePage: page,
        usage: usage,
        logicalMinimum: range.lowerBound,
        logicalMaximum: range.upperBound,
        integerValue: integer,
        reportID: 0
      ),
      receivedAt: MonotonicTimestamp(nanoseconds: 0)
    )
  }

  @Test
  func descriptorHoldsTheLayoutByteForByte() throws {
    let fields = try #require(HIDReportDescriptorParser.parse(descriptor: Self.descriptor)).fields
    #expect(fields.count == 17)
    let layout = fields.map { "\($0.usagePage)/\($0.usage)@\($0.bitOffset)" }
    #expect(layout.prefix(4) == ["1/144@0", "1/146@8", "1/145@16", "1/147@24"])
    #expect(layout[4] == "9/1@32")
    #expect(layout[11] == "9/8@88")
    #expect(layout[12] == "12/547@96")
    #expect(layout.suffix(4) == ["1/48@104", "1/49@112", "1/50@120", "1/53@128"])
  }

  @Test
  func dpadPressesAboveHalfTheRangeFromCenter() throws {
    let driver = try driver()
    let directions: [(usage: UInt32, hat: HatDirection)] = [
      (0x90, .north), (0x91, .south), (0x92, .east), (0x93, .west),
    ]
    for (usage, hat) in directions {
      #expect(parse(driver, page: 1, usage: usage, 255)?.state.hat == hat)
      #expect(parse(driver, page: 1, usage: usage, 0)?.state.hat == .neutral)
    }
  }

  @Test
  func pressureButtonsPressAtThreshold() throws {
    let driver = try driver()
    let buttons: [Control] = [
      .south, .east, .west, .north, .leftShoulder, .rightShoulder,
    ]
    for (index, control) in buttons.enumerated() {
      let usage = UInt32(index + 1)
      #expect(parse(driver, page: 9, usage: usage, 255).contains(.press(control)))
      #expect(parse(driver, page: 9, usage: usage, 0)?.state.pressed.contains(control) == false)
    }
  }

  @Test
  func lowerPressureIsNotAPress() throws {
    let driver = try driver()
    #expect(parse(driver, page: 9, usage: 1, 40)?.state.pressed.contains(.south) == false)
  }

  @Test
  func triggersAreAnalog() throws {
    let driver = try driver()
    #expect(parse(driver, page: 9, usage: 7, 255)?.state.leftTrigger == .max)
    #expect(parse(driver, page: 9, usage: 8, 255)?.state.rightTrigger == .max)
    #expect(parse(driver, page: 9, usage: 7, 0)?.state.leftTrigger == .min)
  }

  @Test
  func menuIsTheConsumerHomeBit() throws {
    let driver = try driver()
    let press = parse(driver, page: 12, usage: 547, 1, range: 0...1)
    #expect(press.contains(.press(.start)))
  }

  @Test
  func signedSticksReachBothEnds() throws {
    let driver = try driver()
    let range = -127...127
    #expect(
      parse(driver, page: 1, usage: 0x30, 127, range: range).contains(.leftStick(x: 1, y: 0))
    )
    #expect(
      parse(driver, page: 1, usage: 0x32, -127, range: range).contains(.rightStick(x: -1, y: 0))
    )
  }

  @Test
  func stickYIsInvertedSoDownIsPositive() throws {
    let driver = try driver()
    let up = parse(driver, page: 1, usage: 0x31, 127, range: -127...127)
    #expect(up?.state.leftStick.y == .min)
  }

  @Test
  func restingStickNearMinusThreeStaysCentered() throws {
    let driver = try driver()
    let rest = parse(driver, page: 1, usage: 0x31, -3, range: -127...127)
    #expect(rest?.state.leftStick == .center)
  }

  @Test
  func capabilitiesListOnlyWhatTheDescriptorDeclares() throws {
    let controls = try driver().capabilities.controls
    #expect(controls.isSuperset(of: [.south, .east, .west, .north, .dpadUp, .dpadLeft, .start]))
    #expect(controls.isSuperset(of: [.leftShoulder, .rightShoulder]))
    #expect(controls.isDisjoint(with: [.back, .leftStickClick, .rightStickClick, .guide]))
  }

  /// SDL's mapping, converted against the descriptor's elements, no longer claims the back,
  /// start and stick-click controls that SDL does not map for this pad.
  @Test
  func sdlMappedControlsListOnlyWhatSDLMaps() throws {
    var order = 0
    func element(_ page: UInt32, _ usage: UInt32, _ range: ClosedRange<Int>) -> HIDElementDescription
    {
      order += 1
      return sdlElement(page, usage, order: order, range: range)
    }
    let elements =
      [0x90, 0x92, 0x91, 0x93].map { element(1, UInt32($0), 0...255) }
      + (1...8).map { element(9, UInt32($0), 0...255) }
      + [element(12, 547, 0...1)]
      + [0x30, 0x31, 0x32, 0x35].map { element(1, UInt32($0), -127...127) }
    let fields = [
      "a:b0", "b:b1", "dpdown:b9", "dpleft:b11", "dpright:b10", "dpup:b8", "guide:b12",
      "leftshoulder:b4", "lefttrigger:b6", "leftx:a0", "lefty:a1~", "rightshoulder:b5",
      "righttrigger:b7", "rightx:a2", "righty:a3~", "x:b2", "y:b3",
    ]
    let converted = try SDLMappingConverter.convert(fields: fields, elements: elements)
    #expect(converted.unmapped.isEmpty)
    let driver = HIDDescriptorDriver(
      model: Self.model,
      reportDescriptor: Data(Self.descriptor),
      usageMap: converted.usageMap
    )
    let controls = driver.capabilities.controls
    #expect(controls.isSuperset(of: [.south, .dpadUp, .dpadRight, .guide, .leftShoulder]))
    #expect(controls.isDisjoint(with: [.back, .start, .leftStickClick, .rightStickClick]))
  }
}
