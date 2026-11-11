import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The 8BitDo Ultimate 2C records.
///
/// The `2DC8:301B` record is checked against `ordered-controls-120s.txt`. The sources of
/// `2DC8:301D` and `2DC8:3109` are the HID usage tables and the Z/Rz layout of
/// `docs/testing/8bitdo-ultimate-2c.md`; no capture of those two identities backs them.
struct EightBitDoUltimate2CTests {
  private static let bluetooth = ControllerModelID(vendorID: 0x2DC8, productID: 0x301B)
  private static let adapter = ControllerModelID(vendorID: 0x2DC8, productID: 0x3109)
  private static let receiver = ControllerModelID(vendorID: 0x2DC8, productID: 0x301C)
  private static let wired = ControllerModelID(vendorID: 0x2DC8, productID: 0x301D)

  /// The button table of `docs/testing/8bitdo-ultimate-2c.md`, written out from that document.
  static let buttonTable: [(usage: UInt32, button: Control)] = [
    (1, .south), (2, .east), (4, .west), (5, .north), (7, .leftShoulder), (8, .rightShoulder),
    (11, .back), (12, .start), (13, .guide), (14, .leftStickClick), (15, .rightStickClick),
  ]

  static func parse(
    _ parser: HIDDescriptorDriver,
    page: UInt32 = 1,
    usage: UInt32,
    _ integer: Int
  ) -> ControllerEvent? {
    parser.parse(
      elementValue: HIDElementValue(
        usagePage: page,
        usage: usage,
        logicalMinimum: 0,
        logicalMaximum: page == 9 ? 1 : 255,
        integerValue: integer,
        reportID: 5
      ),
      receivedAt: MonotonicTimestamp(nanoseconds: 0)
    )
  }

  @Test
  func rightStickSweepMovesBothAxesAndLeavesTriggersAtRest() throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    let right = Self.parse(parser, usage: 0x32, 255)
    #expect(right.contains(.rightStick(x: 1, y: 0)))
    let down = Self.parse(parser, usage: 0x35, 255)
    #expect(down.contains(.rightStick(x: 1, y: 1)))
    #expect(down?.state.leftTrigger == UnipolarValue(normalized: 0))
    #expect(down?.state.rightTrigger == UnipolarValue(normalized: 0))
  }

  @Test(arguments: [UInt32(0x33), 0x34])
  func rxAndRyMapToNothing(usage: UInt32) throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    #expect(Self.parse(parser, usage: usage, 255) == nil)
  }

  @Test
  func adapterStaysXboxXUSBWired() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.adapter))
    #expect(record.physicalProtocolID == .xboxXUSB)
    #expect(record.hidUsageMap == nil)
  }

  @Test
  func receiverMapsNoControls() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.receiver))
    #expect(record.isIdle)
    #expect(record.hidUsageMap == nil)
  }

  @Test
  func wiredDInputReplaysTheBluetoothUsages() throws {
    let parser = HIDDescriptorDriver(
      model: Self.wired,
      usageMap: try catalogUsageMap(0x2DC8, 0x301D)
    )
    for (usage, button) in Self.buttonTable {
      let press = Self.parse(parser, page: 9, usage: usage, 1)
      #expect(press.contains(.press(button)), "usage \(usage)")
    }
    #expect(Self.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
    #expect(Self.parse(parser, usage: 0x33, 255) == nil)
  }

  /// The reports of `ordered-controls-120s.txt`, each as the bytes after the report ID.
  private static func capturedReports() throws -> [[UInt8]] {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { root.deleteLastPathComponent() }
    let capture = root.appendingPathComponent(
      "openspec/changes/0-6-0-alpha-3/evidence/2c-bluetooth-301b/ordered-controls-120s.txt"
    )
    return try String(contentsOf: capture, encoding: .utf8).split(separator: "\n").map {
      $0.split(separator: " ").suffix(11).dropFirst().compactMap { UInt8($0, radix: 16) }
    }
  }

  /// The sign of a stick byte: 0 to 255 spans the axis, so the rest byte `7F` reads just below
  /// zero, the `(-128, -128)` of `ojd-watch-120s.txt`.
  private static func direction(of byte: UInt8) -> Int16 {
    byte < 0x80 ? -1 : 1
  }

  @Test
  func theCapturedReportsMoveTheRightStickWithZAndRzAndLeaveTriggersAtRest() throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    let reports = try Self.capturedReports()
    var rightStickMoved = false
    var leftTriggerPressed = false
    var rightTriggerPressed = false
    for bytes in reports {
      var event: ControllerEvent?
      for (usage, page, byte) in [
        (0x30, 1, bytes[1]), (0x31, 1, bytes[2]), (0x32, 1, bytes[3]), (0x35, 1, bytes[4]),
        (196, 2, bytes[5]), (197, 2, bytes[6]),
      ] {
        event = Self.parse(parser, page: UInt32(page), usage: UInt32(usage), Int(byte)) ?? event
      }
      let state = try #require(event).state
      #expect(state.rightStick.x.rawValue.signum() == Self.direction(of: bytes[3]))
      #expect(state.rightStick.y.rawValue.signum() == Self.direction(of: bytes[4]))
      #expect(state.leftStick.x.rawValue.signum() == Self.direction(of: bytes[1]))
      #expect((state.rightTrigger == UnipolarValue(normalized: 0)) == (bytes[5] == 0))
      #expect((state.leftTrigger == UnipolarValue(normalized: 0)) == (bytes[6] == 0))
      rightStickMoved = rightStickMoved || bytes[3] != 0x7F || bytes[4] != 0x7F
      rightTriggerPressed = rightTriggerPressed || bytes[5] > 0
      leftTriggerPressed = leftTriggerPressed || bytes[6] > 0
    }
    #expect(rightStickMoved && rightTriggerPressed && leftTriggerPressed)
    let rest = try #require(reports.first)
    #expect(rest[5] == 0 && rest[6] == 0)
  }
}
