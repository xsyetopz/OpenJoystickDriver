import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Contract for the Flydigi Vader 4 Pro across its connection modes.
///
/// The controller presents a different identity for each combination of its
/// rear slider position and DInput/XInput toggle, and macOS treats each as a
/// separate device. Bluetooth DInput (`D7D7:0041`) is covered by
/// ``FlydigiParserTests``; the suites here cover the dongle's DInput identity,
/// the Bluetooth XInput identity, and Switch mode.
///
/// The dongle's XInput identity is deliberately absent. It borrows the generic
/// Microsoft Xbox 360 wired VID/PID, which genuine controllers reach over raw
/// USB while this dongle is surfaced through the HID stack. A record declares
/// one transport, so serving both populations from one identity is a design
/// question rather than a parser gap.
///
/// Reports were captured on firmware 6.9.5.5 under macOS 26.5.2 by reading raw
/// HID input through a per-device callback with an explicit buffer.
private enum Vader4Pro {

  // MARK: - Dongle, DInput — 04B4:2412

  /// Composite device; the vendor protocol lives on HID usage page `0xFFA0`.
  enum DongleDInput {
    static let identifier = DeviceIdentifier(vendorID: 0x04B4, productID: 0x2412)
    static let reportLength = 32
    static let magic: [UInt8] = [0x04, 0xFE, 0x66]

    static let neutral: [UInt8] = [
      0x04, 0xFE, 0x66, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0F, 0x00, 0x40, 0xFF,
      0xB5, 0x00, 0x7F, 0x00, 0x7F, 0x00, 0x7F, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xFF, 0x00,
    ]

    enum Offset {
      static let extras = 7
      static let system = 8
      static let faceAndDpad = 9
      static let shoulders = 10
      static let leftStickX = 17
      static let leftTrigger = 23
    }

    static func with(_ index: Int, _ value: UInt8) -> Data {
      var bytes = neutral
      bytes[index] = value
      return Data(bytes)
    }
  }

  // MARK: - Bluetooth, XInput — 045E:02E0

  /// Borrows the Xbox One S Bluetooth identity. Axes are unsigned and centred
  /// at `0x7FFF`, which the descriptor-driven fallback misreads as signed.
  enum BluetoothXInput {
    static let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x02E0)
    static let reportLength = 16
    static let inputReportID: UInt8 = 0x01
    static let homeReportID: UInt8 = 0x02

    static let neutral: [UInt8] = [
      0x01, 0x00, 0x7F, 0xFF, 0x7F, 0x00, 0x7F, 0xFF, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00,
    ]

    enum Offset {
      static let leftStickX = 1
      static let leftStickY = 3
      static let rightStickX = 5
      static let hat = 13
      static let buttons = 14
      static let stickClicks = 15
    }

    static func with(_ index: Int, _ value: UInt8) -> Data {
      var bytes = neutral
      bytes[index] = value
      return Data(bytes)
    }

    /// Writes a 16-bit little-endian axis value at `index`.
    static func axis(_ index: Int, _ value: UInt16) -> Data {
      var bytes = neutral
      bytes[index] = UInt8(value & 0xFF)
      bytes[index + 1] = UInt8(value >> 8)
      return Data(bytes)
    }
  }

  // MARK: - Switch — 057E:2009

  /// Emulates a Nintendo Switch Pro Controller and reuses that record.
  enum SwitchMode {
    static let identifier = DeviceIdentifier(vendorID: 0x057E, productID: 0x2009)
    static let fullReportID: UInt8 = 0x30
    /// Buttons occupy a 24-bit little-endian field; A is `0x000004`.
    static let buttonsOffset = 3
    static let aButtonMask: UInt8 = 0x04
  }
}

private func registry() -> ParserRegistry { ParserRegistry() }

// MARK: - Dongle, DInput

/// `04B4:2412` is absent from the catalog and `FlydigiParser` accepts only the
/// 15-byte Bluetooth report, so these reports currently reach no parser.
@Suite
struct Vader4ProDongleDInputTests {

  private func parser() -> any InputParser {
    registry().parser(for: Vader4Pro.DongleDInput.identifier, transport: .hid)
  }

  /// The identity must reach a parser that recognises the vendor framing
  /// rather than the descriptor-driven fallback, which cannot decode it.
  @Test
  func testIdentityResolvesToTheVendorParser() {
    let name = registry().parserName(for: Vader4Pro.DongleDInput.identifier, transport: .hid)
    #expect(name != "GenericHID", "this identity needs a record rather than the fallback")
  }

  @Test
  func testVendorReportShape() {
    #expect(Vader4Pro.DongleDInput.neutral.count == Vader4Pro.DongleDInput.reportLength)
    #expect(Array(Vader4Pro.DongleDInput.neutral.prefix(3)) == Vader4Pro.DongleDInput.magic)
  }

  @Test
  func testFaceButtonsDecode() throws {
    for (mask, button) in [(UInt8(0x10), Button.a), (0x20, .b), (0x80, .x)] {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.faceAndDpad, mask)
      )
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  @Test
  func testShoulderAndStickButtonsDecode() throws {
    let cases: [(UInt8, Button)] = [
      (0x01, .y), (0x02, .start), (0x04, .leftBumper), (0x08, .rightBumper), (0x40, .leftStick),
      (0x80, .rightStick),
    ]
    for (mask, button) in cases {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.shoulders, mask)
      )
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  /// The D-pad occupies the low nibble of byte 9 in up, right, down, left bit
  /// order, unlike the up, down, left, right order used by other records.
  @Test
  func testDpadDecodesInUpRightDownLeftBitOrder() throws {
    let cases: [(UInt8, DpadDirection)] = [
      (0x01, .north), (0x02, .east), (0x04, .south), (0x08, .west),
    ]
    for (mask, direction) in cases {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.faceAndDpad, mask)
      )
      #expect(events.contains { $0 == .dpadChanged(direction) })
    }
  }

  @Test
  func testGuideDecodes() throws {
    let parser = parser()
    _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
    let events = try parser.parse(
      data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.system, 0x08)
    )
    #expect(events.contains { $0 == .buttonPressed(.guide) })
  }

  /// Analog triggers reach full scale on this transport.
  @Test
  func testTriggersReachFullScale() throws {
    let parser = parser()
    _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
    let events = try parser.parse(
      data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.leftTrigger, 0xFF)
    )
    #expect(events.contains { $0 == .leftTriggerChanged(1.0) })
  }

  @Test
  func testSticksRestCenteredAndDeflectFullScale() throws {
    let parser = parser()
    let neutral = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
    #expect(
      !neutral.contains { event in
        if case .leftStickChanged(let x, let y) = event { return x != 0 || y != 0 }
        return false
      },
      "every axis at 0x7F must read as centered"
    )
    let events = try parser.parse(
      data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.leftStickX, 0xFF)
    )
    #expect(
      events.contains { event in
        if case .leftStickChanged(let x, _) = event { return x > 0.9 }
        return false
      }
    )
  }

  /// Byte 7 carries one bit per extra button. In every other mode these
  /// controls repeat existing buttons, so this transport is the only one where
  /// they can be bound separately.
  @Test
  func testExtraButtonsEmitDistinctEvents() throws {
    var produced: Set<Button> = []
    for mask: UInt8 in [0x01, 0x02, 0x04, 0x08, 0x10, 0x20] {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.DongleDInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.DongleDInput.with(Vader4Pro.DongleDInput.Offset.extras, mask)
      )
      let pressed = events.compactMap { event -> Button? in
        if case .buttonPressed(let button) = event { return button }
        return nil
      }
      #expect(!pressed.isEmpty, "extra button 0x\(String(mask, radix: 16)) must emit an event")
      produced.formUnion(pressed)
    }
    #expect(produced.count == 6, "each extra button must map to its own Button case")
  }
}

/// Vibration on the dongle's DInput transport, verified by driving the motors
/// on hardware.
@Suite
struct Vader4ProDongleDInputRumbleTests {

  private func rumbleParser() -> (any PhysicalHIDRumbleOutput)? {
    registry().parser(for: Vader4Pro.DongleDInput.identifier, transport: .hid)
      as? any PhysicalHIDRumbleOutput
  }

  @Test
  func testParserAdvertisesBothMotors() throws {
    let parser = try #require(rumbleParser())
    #expect(parser.supportsPhysicalRumble)
    #expect(parser.physicalRumbleMotors == [.leftMain, .rightMain])
  }

  /// The frame the controller accepts is `05 0F <left> <right>` on report 5.
  @Test
  func testRumbleFrameMatchesTheVerifiedVendorFormat() throws {
    let parser = try #require(rumbleParser())
    let report = parser.physicalRumbleReport(left: 0x40, right: 0x80, lt: 0, rt: 0)
    #expect(report.reportID == 0x05)
    #expect(report.bytes == [0x05, 0x0F, 0x40, 0x80])
  }

  /// Magnitude is honoured, so the two motors must be independently settable.
  @Test
  func testMotorsAreIndependentlyAddressable() throws {
    let parser = try #require(rumbleParser())
    let leftOnly = parser.physicalRumbleReport(left: 0xFF, right: 0x00, lt: 0, rt: 0)
    let rightOnly = parser.physicalRumbleReport(left: 0x00, right: 0xFF, lt: 0, rt: 0)
    #expect(leftOnly.bytes[2] == 0xFF && leftOnly.bytes[3] == 0x00)
    #expect(rightOnly.bytes[2] == 0x00 && rightOnly.bytes[3] == 0xFF)
  }

  /// The effect latches until a zero-magnitude frame arrives, so the stop must
  /// keep the command byte rather than being an empty or all-zero payload.
  @Test
  func testStopFrameKeepsTheCommandByte() throws {
    let parser = try #require(rumbleParser())
    let stop = parser.physicalRumbleReport(left: 0, right: 0, lt: 0, rt: 0)
    #expect(stop.bytes == [0x05, 0x0F, 0x00, 0x00])
  }

  /// Sustained vibration needs the frame resent, so the parser must declare a
  /// non-zero minimum interval rather than relying on a single write.
  @Test
  func testDeclaresAResendInterval() throws {
    let parser = try #require(rumbleParser())
    #expect(parser.minimumPhysicalOutputIntervalNanoseconds > 0)
  }

  /// The controller has no trigger actuators, so those arguments must not
  /// reach the wire.
  @Test
  func testTriggerMagnitudesAreIgnored() throws {
    let parser = try #require(rumbleParser())
    let withTriggers = parser.physicalRumbleReport(left: 0x10, right: 0x20, lt: 0xFF, rt: 0xFF)
    #expect(withTriggers.bytes == [0x05, 0x0F, 0x10, 0x20])
  }
}

// MARK: - Bluetooth, XInput

/// `045E:02E0` has no catalog record, so it falls back to `GenericHIDParser`.
/// Most controls survive that, but the sticks are unsigned and the Home button
/// arrives on a second report ID.
@Suite
struct Vader4ProBluetoothXInputTests {

  private func parser() -> any InputParser {
    registry().parser(for: Vader4Pro.BluetoothXInput.identifier, transport: .hid)
  }

  @Test
  func testIdentityHasADedicatedParser() {
    let name = registry().parserName(for: Vader4Pro.BluetoothXInput.identifier, transport: .hid)
    #expect(name != "GenericHID", "this identity needs a record rather than the fallback")
  }

  @Test
  func testNeutralReportShape() {
    #expect(Vader4Pro.BluetoothXInput.neutral.count == Vader4Pro.BluetoothXInput.reportLength)
    #expect(Vader4Pro.BluetoothXInput.neutral[0] == Vader4Pro.BluetoothXInput.inputReportID)
  }

  /// Axes are unsigned and centred at `0x7FFF`. Read as signed, everything at
  /// or above `0x8000` wraps negative, which presents as the sticks working in
  /// only one quadrant.
  @Test
  func testUnsignedAxesDecodeAcrossTheFullRange() throws {
    let parser = parser()
    _ = try parser.parse(data: Data(Vader4Pro.BluetoothXInput.neutral))

    let right = try parser.parse(
      data: Vader4Pro.BluetoothXInput.axis(Vader4Pro.BluetoothXInput.Offset.leftStickX, 0xFFFF)
    )
    #expect(
      right.contains { event in
        if case .leftStickChanged(let x, _) = event { return x > 0.9 }
        return false
      },
      "0xFFFF must read as full positive, not negative"
    )

    let left = try parser.parse(
      data: Vader4Pro.BluetoothXInput.axis(Vader4Pro.BluetoothXInput.Offset.leftStickX, 0x0000)
    )
    #expect(
      left.contains { event in
        if case .leftStickChanged(let x, _) = event { return x < -0.9 }
        return false
      }
    )
  }

  @Test
  func testNeutralAxesReadAsCentered() throws {
    let events = try parser().parse(data: Data(Vader4Pro.BluetoothXInput.neutral))
    #expect(
      !events.contains { event in
        if case .leftStickChanged(let x, let y) = event { return abs(x) > 0.1 || abs(y) > 0.1 }
        return false
      },
      "0x7FFF must read as centered"
    )
  }

  @Test
  func testFaceButtonsDecode() throws {
    let cases: [(UInt8, Button)] = [
      (0x01, .a), (0x02, .b), (0x04, .x), (0x08, .y), (0x10, .leftBumper), (0x20, .rightBumper),
      (0x40, .back), (0x80, .start),
    ]
    for (mask, button) in cases {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.BluetoothXInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.BluetoothXInput.with(Vader4Pro.BluetoothXInput.Offset.buttons, mask)
      )
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  @Test
  func testStickClicksDecode() throws {
    for (mask, button) in [(UInt8(0x01), Button.leftStick), (0x02, .rightStick)] {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.BluetoothXInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.BluetoothXInput.with(Vader4Pro.BluetoothXInput.Offset.stickClicks, mask)
      )
      #expect(events.contains { $0 == .buttonPressed(button) })
    }
  }

  @Test
  func testHatDecodes() throws {
    let cases: [(UInt8, DpadDirection)] = [(1, .north), (3, .east), (5, .south), (7, .west)]
    for (value, direction) in cases {
      let parser = parser()
      _ = try parser.parse(data: Data(Vader4Pro.BluetoothXInput.neutral))
      let events = try parser.parse(
        data: Vader4Pro.BluetoothXInput.with(Vader4Pro.BluetoothXInput.Offset.hat, value)
      )
      #expect(events.contains { $0 == .dpadChanged(direction) })
    }
  }

  /// Home arrives on report `0x02` rather than the main input report, so a
  /// parser that only decodes report `0x01` never sees it.
  @Test
  func testHomeDecodesFromItsOwnReport() throws {
    let parser = parser()
    _ = try parser.parse(data: Data(Vader4Pro.BluetoothXInput.neutral))
    var home = [UInt8](repeating: 0, count: 2)
    home[0] = Vader4Pro.BluetoothXInput.homeReportID
    home[1] = 0x01
    let events = try parser.parse(data: Data(home))
    #expect(events.contains { $0 == .buttonPressed(.guide) })
  }
}

// MARK: - Switch

/// Switch mode already works through the shared Switch Pro record. These tests
/// lock that in so a future catalog change cannot silently reroute it.
@Suite
struct Vader4ProSwitchModeTests {

  @Test
  func testIdentityResolvesToTheSwitchProParser() {
    let name = registry().parserName(for: Vader4Pro.SwitchMode.identifier, transport: .hid)
    #expect(name == "SwitchPro")
  }

  @Test
  func testParserIsReachedOverHIDTransport() {
    let parser = registry().parser(for: Vader4Pro.SwitchMode.identifier, transport: .hid)
    #expect(parser is SwitchProParser)
  }

  /// The controller streams the Switch Pro full input report, so the parser
  /// must accept report `0x30`.
  @Test
  func testFullInputReportDecodesAButtonPress() throws {
    let parser = registry().parser(for: Vader4Pro.SwitchMode.identifier, transport: .hid)
    var neutral = [UInt8](repeating: 0, count: 49)
    neutral[0] = Vader4Pro.SwitchMode.fullReportID
    _ = try parser.parse(data: Data(neutral))

    var pressed = neutral
    pressed[Vader4Pro.SwitchMode.buttonsOffset] = Vader4Pro.SwitchMode.aButtonMask
    let events = try parser.parse(data: Data(pressed))
    #expect(events.contains { $0 == .buttonPressed(.a) })
  }
}
