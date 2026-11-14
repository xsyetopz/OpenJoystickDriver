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

  /// L4 sets button usage 3 and R4 usage 6 over Bluetooth LE (`ordered-controls-120s.txt`) and
  /// on the receiver (`2c-receiver-301c/rear-unassigned-60s.txt`).
  @Test(arguments: [UInt16(0x301B), 0x301C])
  func rearButtonsAreFirstPaddles(productID: UInt16) throws {
    let parser = HIDDescriptorDriver(
      model: ControllerModelID(vendorID: 0x2DC8, productID: productID),
      usageMap: try catalogUsageMap(0x2DC8, productID)
    )
    #expect(Self.parse(parser, page: 9, usage: 3, 1).contains(.press(.leftPaddle1)))
    #expect(Self.parse(parser, page: 9, usage: 6, 1).contains(.press(.rightPaddle1)))
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
  func receiverServesLinkedPadThroughItsDescriptor() throws {
    let record = try #require(ProtocolDriverRegistry().record(for: Self.receiver))
    #expect(!record.isIdle)
  }

  /// Each report of the captures leaves the pad's power unset: the battery byte is constant.
  @Test(arguments: [
    (UInt16(0x301B), "2c-bluetooth-301b/ordered-controls-120s.txt", 11),
    (UInt16(0x301C), "2c-receiver-301c/ordered-controls-150s.txt", 10),
  ])
  func recordsExposeNoBattery(productID: UInt16, capture: String, length: Int) throws {
    let model = ControllerModelID(vendorID: 0x2DC8, productID: productID)
    let parser = HIDDescriptorDriver(model: model, usageMap: try catalogUsageMap(0x2DC8, productID))
    for bytes in try Self.capturedReports(capture, length: length) {
      _ = Self.parse(parser, usage: 0x30, Int(bytes[3]))
    }
    #expect(parser.power == nil)
  }

  @Test(arguments: [UInt16(0x301C), 0x301D])
  func dinputIdentitiesReplayBluetoothUsages(productID: UInt16) throws {
    let parser = HIDDescriptorDriver(
      model: ControllerModelID(vendorID: 0x2DC8, productID: productID),
      usageMap: try catalogUsageMap(0x2DC8, productID)
    )
    for (usage, button) in Self.buttonTable {
      let press = Self.parse(parser, page: 9, usage: usage, 1)
      #expect(press.contains(.press(button)), "usage \(usage)")
    }
    #expect(Self.parse(parser, usage: 0x32, 255).contains(.rightStick(x: 1, y: 0)))
    #expect(Self.parse(parser, usage: 0x33, 255) == nil)
  }

  /// The reports of a capture under `evidence/`, each as the bytes after the report ID.
  private static func capturedReports(_ path: String, length: Int) throws -> [[UInt8]] {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 { root.deleteLastPathComponent() }
    let capture = root.appendingPathComponent("openspec/changes/0-6-0-alpha-3/evidence/\(path)")
    return try String(contentsOf: capture, encoding: .utf8).split(separator: "\n")
      .filter { $0.contains(" rx ") }
      .map {
        $0.split(separator: " ").suffix(length).dropFirst().compactMap { UInt8($0, radix: 16) }
      }
  }

  /// The sign of a stick byte: 0 to 255 spans the axis, so the rest byte `7F` reads just below
  /// zero, the `(-128, -128)` of `ojd-watch-120s.txt`.
  private static func direction(of byte: UInt8) -> Int16 {
    byte < 0x80 ? -1 : 1
  }

  @Test
  func capturedReportsMoveRightStickWithZAndRzAndLeaveTriggersAtRest() throws {
    let parser = HIDDescriptorDriver(
      model: Self.bluetooth,
      usageMap: try catalogUsageMap(0x2DC8, 0x301B)
    )
    let capture = "2c-bluetooth-301b/ordered-controls-120s.txt"
    let reports = try Self.capturedReports(capture, length: 11)
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

  /// The receiver's descriptor puts button usage `n` on bit `n - 1` of bytes 1 and 2, X, Y, Z
  /// and Rz on bytes 4 to 7, Accelerator on byte 8 and Brake on byte 9.
  @Test
  func capturedReceiverReportsDecodeEveryButtonStickAndTrigger() throws {
    let parser = HIDDescriptorDriver(
      model: Self.receiver,
      usageMap: try catalogUsageMap(0x2DC8, 0x301C)
    )
    let pressed = Dictionary(uniqueKeysWithValues: Self.buttonTable.map { ($0.usage, $0.button) })
    var seen = Set<Control>()
    let capture = "2c-receiver-301c/ordered-controls-150s.txt"
    for bytes in try Self.capturedReports(capture, length: 10) {
      var event: ControllerEvent?
      for (usage, page, byte) in [
        (0x30, 1, bytes[3]), (0x31, 1, bytes[4]), (0x32, 1, bytes[5]), (0x35, 1, bytes[6]),
        (196, 2, bytes[7]), (197, 2, bytes[8]),
      ] {
        event = Self.parse(parser, page: UInt32(page), usage: UInt32(usage), Int(byte)) ?? event
      }
      for (usage, button) in pressed {
        let bits = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        let down = bits >> (usage - 1) & 1
        event = Self.parse(parser, page: 9, usage: usage, Int(down)) ?? event
        if down == 1 { seen.insert(button) }
        #expect(try #require(event).state.pressed.contains(button) == (down == 1), "usage \(usage)")
      }
      let state = try #require(event).state
      #expect(state.rightStick.x.rawValue.signum() == Self.direction(of: bytes[5]))
      #expect(state.leftStick.y.rawValue.signum() == Self.direction(of: bytes[4]))
      #expect((state.rightTrigger == UnipolarValue(normalized: 0)) == (bytes[7] == 0))
      #expect((state.leftTrigger == UnipolarValue(normalized: 0)) == (bytes[8] == 0))
    }
    #expect(seen == Set(pressed.values))
  }
}
