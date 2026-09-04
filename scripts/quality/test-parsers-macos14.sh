#!/usr/bin/env bash
# Focused parser regression harness compiled for a macOS 14 deployment target.
# It uses a plain executable so parser compatibility is checked independently
# of the Swift Testing runtime.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_DIR="${OJD_MACOS14_HARNESS_DIR:-/tmp/ojd-parser-harness}"
SCRATCH_DIR="${OJD_MACOS14_HARNESS_SCRATCH:-/tmp/ojd-parser-harness-build}"
CACHE_DIR="${OJD_MACOS14_HARNESS_CACHE:-/tmp/ojd-parser-harness-cache}"
MODULE_CACHE_DIR="${OJD_MACOS14_HARNESS_MODULE_CACHE:-/tmp/ojd-clang-module-cache}"
mkdir -p "$HARNESS_DIR/Sources/OJDParserHarness"
mkdir -p "$SCRATCH_DIR"
mkdir -p "$CACHE_DIR"
mkdir -p "$MODULE_CACHE_DIR"

cat > "$HARNESS_DIR/Package.swift" <<PACKAGE_SWIFT
// swift-tools-version:6.3
import PackageDescription

let package = Package(
  name: "OJDParserHarness",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "$PROJECT_DIR")
  ],
  targets: [
    .executableTarget(
      name: "OJDParserHarness",
      dependencies: [.product(name: "OpenJoystickDriverKit", package: "OpenJoystickDriver")]
    )
  ]
)
PACKAGE_SWIFT

cat > "$HARNESS_DIR/Sources/OJDParserHarness/main.swift" <<'HARNESS_SWIFT'
import Foundation
import OpenJoystickDriverKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

func hasEvent(_ events: [ControllerEvent], _ expected: ControllerEvent) -> Bool {
  events.contains(expected)
}

func writeInt16LE(_ value: Int16, into bytes: inout [UInt8], at offset: Int) {
  let raw = UInt16(bitPattern: value)
  bytes[offset] = UInt8(truncatingIfNeeded: raw)
  bytes[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
}

func makeSteamControllerReport(
  b8: UInt8 = 0,
  b9: UInt8 = 0,
  b10: UInt8 = 0,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  leftX: Int16 = 0,
  leftY: Int16 = 0,
  rightPadX: Int16 = 0,
  rightPadY: Int16 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x01
  report[3] = 60
  report[8] = b8
  report[9] = b9
  report[10] = b10
  report[11] = leftTrigger
  report[12] = rightTrigger
  writeInt16LE(leftX, into: &report, at: 16)
  writeInt16LE(leftY, into: &report, at: 18)
  writeInt16LE(rightPadX, into: &report, at: 20)
  writeInt16LE(rightPadY, into: &report, at: 22)
  return Data(report)
}

func makeSteamWirelessReport(status: UInt8) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x03
  report[3] = 1
  report[4] = status
  return Data(report)
}

func makeSteamStatusReport() -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = 0x04
  report[3] = 11
  report[16] = 85
  return Data(report)
}

func makeDS3Report(
  button0: UInt8 = 0,
  button1: UInt8 = 0,
  ps: Bool = false,
  leftX: UInt8 = 128,
  leftY: UInt8 = 128,
  rightX: UInt8 = 128,
  rightY: UInt8 = 128,
  l2Analog: UInt8 = 0,
  r2Analog: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 49)
  report[0] = 0x01
  report[1] = 0x00
  report[2] = button0
  report[3] = button1
  report[4] = ps ? 0x01 : 0x00
  report[6] = leftX
  report[7] = leftY
  report[8] = rightX
  report[9] = rightY
  report[18] = l2Analog
  report[19] = r2Analog
  return Data(report)
}

func updateCRC32(_ current: UInt32, byte: UInt8) -> UInt32 {
  var crc = current ^ UInt32(byte)
  for _ in 0..<8 {
    if crc & 1 == 1 {
      crc = (crc >> 1) ^ 0xEDB8_8320
    } else {
      crc >>= 1
    }
  }
  return crc
}

func dualSenseBluetoothCRC32(_ report: [UInt8]) -> UInt32 {
  var crc = updateCRC32(0xFFFF_FFFF, byte: 0xA1)
  for byte in report.dropLast(4) {
    crc = updateCRC32(crc, byte: byte)
  }
  return ~crc
}

func makeDualSenseUSBReport(
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x01
  report[1] = leftStickX
  report[2] = leftStickY
  report[3] = rightStickX
  report[4] = rightStickY
  report[5] = leftTrigger
  report[6] = rightTrigger
  report[8] = buttons0
  report[9] = buttons1
  report[10] = buttons2
  return Data(report)
}

func makeDualSenseBluetoothReport(
  leftStickX: UInt8 = 128,
  leftStickY: UInt8 = 128,
  rightStickX: UInt8 = 128,
  rightStickY: UInt8 = 128,
  leftTrigger: UInt8 = 0,
  rightTrigger: UInt8 = 0,
  buttons0: UInt8 = 0x08,
  buttons1: UInt8 = 0,
  buttons2: UInt8 = 0
) -> Data {
  var report = [UInt8](repeating: 0, count: 78)
  report[0] = 0x31
  report[2] = leftStickX
  report[3] = leftStickY
  report[4] = rightStickX
  report[5] = rightStickY
  report[6] = leftTrigger
  report[7] = rightTrigger
  report[9] = buttons0
  report[10] = buttons1
  report[11] = buttons2
  let crc = dualSenseBluetoothCRC32(report)
  report[74] = UInt8(truncatingIfNeeded: crc)
  report[75] = UInt8(truncatingIfNeeded: crc >> 8)
  report[76] = UInt8(truncatingIfNeeded: crc >> 16)
  report[77] = UInt8(truncatingIfNeeded: crc >> 24)
  return Data(report)
}

func writeSwitchStick(x: UInt16, y: UInt16, into report: inout [UInt8], at offset: Int) {
  report[offset] = UInt8(truncatingIfNeeded: x)
  report[offset + 1] = UInt8(truncatingIfNeeded: (x >> 8) | ((y & 0x0F) << 4))
  report[offset + 2] = UInt8(truncatingIfNeeded: y >> 4)
}

func makeSwitchProReport(buttons: UInt32 = 0, leftX: UInt16 = 2048, leftY: UInt16 = 2048, rightX: UInt16 = 2048, rightY: UInt16 = 2048) -> Data {
  var report = [UInt8](repeating: 0, count: 49)
  report[0] = 0x30
  report[3] = UInt8(truncatingIfNeeded: buttons)
  report[4] = UInt8(truncatingIfNeeded: buttons >> 8)
  report[5] = UInt8(truncatingIfNeeded: buttons >> 16)
  writeSwitchStick(x: leftX, y: leftY, into: &report, at: 6)
  writeSwitchStick(x: rightX, y: rightY, into: &report, at: 9)
  return Data(report)
}



func runProfileMetadataChecks() {
  let registry = ParserRegistry()
  let ds3 = DeviceIdentifier(vendorID: 1356, productID: 616)
  let ds3Profile = registry.runtimeProfile(for: ds3)
  require(registry.parserName(for: ds3) == "DS3", "DS3 profile should select DS3 parser")
  require(ds3Profile.protocolVariant == .dualShock3, "DS3 profile should use dualShock3 variant")
  require(
    ds3Profile.mappingFlags.isEmpty,
    "DS3 profile should not advertise unimplemented sensors or battery status"
  )

  for id in [
    DeviceIdentifier(vendorID: 1356, productID: 3302),
    DeviceIdentifier(vendorID: 1356, productID: 3570),
  ] {
    let profile = registry.runtimeProfile(for: id)
    require(registry.parserName(for: id) == "DualSense", "DualSense profile should select parser")
    require(profile.protocolVariant == .dualSense, "DualSense profile should use dualSense variant")
    require(
      profile.mappingFlags == ["touchpad", "microphoneMute"],
      "DualSense profile should expose operational input flags"
    )
  }

  let steamWired = DeviceIdentifier(vendorID: 10462, productID: 4354)
  let steamWiredProfile = registry.runtimeProfile(for: steamWired)
  require(registry.parserName(for: steamWired) == "SteamController", "Steam wired should select parser")
  require(steamWiredProfile.protocolVariant == .steamController, "Steam wired should use variant")
  require(
    steamWiredProfile.mappingFlags == ["lizardMode", "trackpads"],
    "Steam wired profile should expose operational flags"
  )

  let steamWireless = DeviceIdentifier(vendorID: 10462, productID: 4418)
  let steamWirelessProfile = registry.runtimeProfile(for: steamWireless)
  require(
    registry.parserName(for: steamWireless) == "SteamController",
    "Steam wireless receiver should select parser"
  )
  require(
    steamWirelessProfile.protocolVariant == .steamController,
    "Steam wireless receiver should use variant"
  )
  require(
    steamWirelessProfile.mappingFlags == [
      "lizardMode", "trackpads", "wirelessReceiver",
    ],
    "Steam wireless receiver profile must retain wirelessReceiver lifecycle flag"
  )

  let switchPro = DeviceIdentifier(vendorID: 1406, productID: 8201)
  let switchProfile = registry.runtimeProfile(for: switchPro)
  require(registry.parserName(for: switchPro) == "SwitchPro", "Switch Pro profile should select parser")
  require(switchProfile.protocolVariant == .switchPro, "Switch Pro profile should use variant")
  require(
    switchProfile.mappingFlags == ["usbHandshake"],
    "Switch Pro profile should not advertise unimplemented calibration, rumble, or IMU"
  )
}

func runSteamInputAndFeatureChecks() throws {
  let parser = ParserRegistry().parser(for: DeviceIdentifier(vendorID: 10462, productID: 4354))
  _ = try parser.parse(data: makeSteamControllerReport())
  let events = try parser.parse(data: makeSteamControllerReport(
    b8: 0xFC,
    b9: 0x70,
    b10: 0x44,
    leftTrigger: 255,
    rightTrigger: 128,
    leftX: 32767,
    leftY: -32767,
    rightPadX: -32767,
    rightPadY: 32767
  ))
  for expected in [Button.a, .b, .x, .y, .leftBumper, .rightBumper, .back, .guide, .start, .leftStick, .rightStick] {
    require(hasEvent(events, .buttonPressed(expected)), "Steam primary input should press \(expected)")
  }
  require(hasEvent(events, .leftTriggerChanged(1.0)), "Steam should parse left trigger")
  require(hasEvent(events, .rightTriggerChanged(128.0 / 255.0)), "Steam should parse right trigger")
  require(hasEvent(events, .leftStickChanged(x: 1.0, y: 1.0)), "Steam should parse left stick")
  require(hasEvent(events, .rightStickChanged(x: -1.0, y: -1.0)), "Steam should parse right pad as right stick")

  let leftPadOnly = SteamControllerParser()
  _ = try leftPadOnly.parse(data: makeSteamControllerReport())
  let leftPadOnlyEvents = try leftPadOnly.parse(data: makeSteamControllerReport(b10: 0x08, leftX: 32767, leftY: -32767))
  require(!hasEvent(leftPadOnlyEvents, .leftStickChanged(x: 1.0, y: 1.0)), "Steam left-pad-only coordinates should not create left-stick motion")
  require(hasEvent(leftPadOnlyEvents, .buttonPressed(.genericButton4)), "Steam left pad touch should emit touch button")

  let leftPadAndJoy = SteamControllerParser()
  _ = try leftPadAndJoy.parse(data: makeSteamControllerReport())
  let leftPadAndJoyEvents = try leftPadAndJoy.parse(data: makeSteamControllerReport(b10: 0x88, leftX: 32767, leftY: -32767))
  require(hasEvent(leftPadAndJoyEvents, .leftStickChanged(x: 1.0, y: 1.0)), "Steam lpad+joy bit should allow left-stick motion")
  require(hasEvent(leftPadAndJoyEvents, .buttonPressed(.genericButton4)), "Steam lpad+joy bit should emit touch button")

  let dpad = SteamControllerParser()
  _ = try dpad.parse(data: makeSteamControllerReport())
  let upEvents = try dpad.parse(data: makeSteamControllerReport(b9: 0x01))
  let rightEvents = try dpad.parse(data: makeSteamControllerReport(b9: 0x02))
  let downEvents = try dpad.parse(data: makeSteamControllerReport(b9: 0x08))
  let leftEvents = try dpad.parse(data: makeSteamControllerReport(b9: 0x04))
  require(hasEvent(upEvents, .dpadChanged(.north)), "Steam should parse d-pad north")
  require(hasEvent(rightEvents, .dpadChanged(.east)), "Steam should parse d-pad east")
  require(hasEvent(downEvents, .dpadChanged(.south)), "Steam should parse d-pad south")
  require(hasEvent(leftEvents, .dpadChanged(.west)), "Steam should parse d-pad west")

  let featureParser = SteamControllerParser()
  let startup = featureParser.hidStartupFeatureReports()
  require(startup.map(\.reportID) == [0, 0], "Steam lizard startup reports should use report ID 0")
  require(startup.map { $0.bytes.count } == [64, 64], "Steam lizard startup reports should be 64 bytes")
  require(startup[0].bytes[0] == 0x81, "Steam startup should clear digital mappings")
  require(Array(startup[1].bytes.prefix(8)) == [0x87, 6, 0x07, 0x07, 0, 0x08, 0x07, 0], "Steam startup should disable trackpad mouse modes")
  let shutdown = featureParser.hidShutdownFeatureReports()
  require(shutdown.map(\.reportID) == [0, 0], "Steam shutdown reports should use report ID 0")
  require(shutdown[0].bytes[0] == 0x85, "Steam shutdown should restore digital mappings")
  require(shutdown[1].bytes[0] == 0x8E, "Steam shutdown should load default settings")
}

func runSteamStatusFallbackCheck() throws {
  let parser = SteamControllerParser(isWirelessReceiver: true)
  let statusEvents = try parser.parse(data: makeSteamStatusReport())
  require(statusEvents.isEmpty, "Steam status report should not emit input events")
  require(parser.consumeInputConnectionStateChange() == .connected, "Steam status report should mark receiver connected")
  let inputEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
  require(hasEvent(inputEvents, .buttonPressed(.a)), "Steam input after status fallback should parse A press")
}

func runSteamWirelessConnectDisconnectCheck() throws {
  let parser = SteamControllerParser(isWirelessReceiver: true)
  require(parser.requiresInputConnectionBeforeOutput, "Steam wireless receiver should gate output")

  let preConnectEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
  require(preConnectEvents.isEmpty, "Steam wireless input before logical connect should be ignored")

  let connectEvents = try parser.parse(data: makeSteamWirelessReport(status: 0x02))
  require(connectEvents.isEmpty, "Steam wireless connect report should not emit input")
  require(parser.consumeInputConnectionStateChange() == .connected, "Steam wireless connect report should emit connected lifecycle")
  require(parser.consumeInputConnectionStateChange() == nil, "Steam wireless lifecycle should be consumed once")

  let inputEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
  require(hasEvent(inputEvents, .buttonPressed(.a)), "Steam wireless input after connect should parse A press")

  let disconnectEvents = try parser.parse(data: makeSteamWirelessReport(status: 0x01))
  require(disconnectEvents.isEmpty, "Steam wireless disconnect report should not emit input")
  require(parser.consumeInputConnectionStateChange() == .disconnected, "Steam wireless disconnect report should emit disconnected lifecycle")

  let postDisconnectEvents = try parser.parse(data: makeSteamControllerReport(b8: 0x80))
  require(postDisconnectEvents.isEmpty, "Steam wireless input after disconnect should be ignored")
}

func runDS3InputChecks() throws {
  let parser = DS3Parser()
  _ = try parser.parse(data: makeDS3Report())
  let buttonEvents = try parser.parse(data: makeDS3Report(button0: 0x3F, button1: 0xFF, ps: true))
  for expected in [Button.back, .leftStick, .rightStick, .start, .l2Digital, .r2Digital, .l1, .r1, .triangle, .circle, .cross, .square, .ps] {
    require(hasEvent(buttonEvents, .buttonPressed(expected)), "DS3 primary input should press \(expected)")
  }
  require(hasEvent(buttonEvents, .dpadChanged(.northEast)), "DS3 should parse d-pad north-east")

  let axisParser = DS3Parser()
  _ = try axisParser.parse(data: makeDS3Report())
  let axisEvents = try axisParser.parse(data: makeDS3Report(
    leftX: 255,
    leftY: 0,
    rightX: 0,
    rightY: 255,
    l2Analog: 255,
    r2Analog: 128
  ))
  require(hasEvent(axisEvents, .leftStickChanged(x: 1.0, y: 1.0)), "DS3 should parse left stick")
  require(hasEvent(axisEvents, .rightStickChanged(x: -1.0, y: -1.0)), "DS3 should parse right stick")
  require(hasEvent(axisEvents, .leftTriggerChanged(1.0)), "DS3 should parse left analog trigger")
  require(hasEvent(axisEvents, .rightTriggerChanged(128.0 / 255.0)), "DS3 should parse right analog trigger")
}

func runDS3TransportAndBluetoothCheck() throws {
  let parser = DS3Parser()
  require(parser.hidStartupFeatureReadRequests(transport: "USB") == [
    PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
    PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
  ], "DS3 USB startup reads should match Linux")
  require(parser.hidStartupFeatureReadRequests(transport: "Bluetooth").isEmpty, "DS3 Bluetooth should not send USB feature reads")
  require(parser.hidStartupFeatureReadRequests(transport: nil).isEmpty, "DS3 unknown transport should not send USB feature reads")
  require(parser.hidStartupFeatureReports(transport: "USB").isEmpty, "DS3 USB should not send Bluetooth feature report")
  require(parser.hidStartupFeatureReports(transport: "Bluetooth") == [
    PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 0x03, 0x00, 0x00])
  ], "DS3 Bluetooth operational feature report should match Linux")
  var bogus = Array(makeDS3Report(button0: 0x10, button1: 0x40, leftX: 255, l2Analog: 255))
  bogus[1] = 0xFF
  let events = try parser.parse(data: Data(bogus))
  require(events.isEmpty, "DS3 bogus Bluetooth status report should be ignored")
}


func runDualSenseUSBChecks() throws {
  let parser = ParserRegistry().parser(for: DeviceIdentifier(vendorID: 1356, productID: 3302))
  _ = try parser.parse(data: makeDualSenseUSBReport())
  let events = try parser.parse(data: makeDualSenseUSBReport(
    leftStickX: 255,
    leftStickY: 0,
    rightStickX: 0,
    rightStickY: 255,
    leftTrigger: 255,
    rightTrigger: 128,
    buttons0: 0x28,
    buttons1: 0x30,
    buttons2: 0x03
  ))
  require(hasEvent(events, .leftStickChanged(x: 1.0, y: 1.0)), "DualSense USB should parse left stick")
  require(hasEvent(events, .rightStickChanged(x: -1.0, y: -1.0)), "DualSense USB should parse right stick")
  require(hasEvent(events, .leftTriggerChanged(1.0)), "DualSense USB should parse left trigger")
  require(hasEvent(events, .rightTriggerChanged(128.0 / 255.0)), "DualSense USB should parse right trigger")
  for expected in [Button.cross, .share, .options, .ps, .touchpad] {
    require(hasEvent(events, .buttonPressed(expected)), "DualSense USB should press \(expected)")
  }

  let micParser = DualSenseParser()
  _ = try micParser.parse(data: makeDualSenseUSBReport())
  let micEvents = try micParser.parse(data: makeDualSenseUSBReport(buttons2: 0x04))
  require(hasEvent(micEvents, .buttonPressed(.genericButton1)), "DualSense USB should parse mic mute")
}

func runDualSenseUnknownReportCheck() throws {
  let parser = DualSenseParser()
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x02
  report[1] = 255
  report[2] = 0
  report[5] = 255
  report[8] = 0x28
  let events = try parser.parse(data: Data(report))
  require(events.isEmpty, "DualSense unknown report IDs should be ignored")
}

func runDualSenseBluetoothCRCCheck() throws {
  let parser = DualSenseParser()
  _ = try parser.parse(data: makeDualSenseBluetoothReport())
  let events = try parser.parse(data: makeDualSenseBluetoothReport(
    leftStickX: 255,
    leftStickY: 0,
    rightStickX: 0,
    rightStickY: 255,
    leftTrigger: 255,
    rightTrigger: 128,
    buttons0: 0x28,
    buttons1: 0x30,
    buttons2: 0x07
  ))
  require(hasEvent(events, .leftStickChanged(x: 1.0, y: 1.0)), "DualSense Bluetooth should parse left stick")
  require(hasEvent(events, .rightStickChanged(x: -1.0, y: -1.0)), "DualSense Bluetooth should parse right stick")
  require(hasEvent(events, .leftTriggerChanged(1.0)), "DualSense Bluetooth should parse left trigger")
  require(hasEvent(events, .rightTriggerChanged(128.0 / 255.0)), "DualSense Bluetooth should parse right trigger")
  require(hasEvent(events, .buttonPressed(.cross)), "DualSense Bluetooth should parse Cross")
  require(hasEvent(events, .buttonPressed(.share)), "DualSense Bluetooth should parse Create/Share")
  require(hasEvent(events, .buttonPressed(.options)), "DualSense Bluetooth should parse Options")
  require(hasEvent(events, .buttonPressed(.ps)), "DualSense Bluetooth should parse PS")
  require(hasEvent(events, .buttonPressed(.touchpad)), "DualSense Bluetooth should parse touchpad")
  require(hasEvent(events, .buttonPressed(.genericButton1)), "DualSense Bluetooth should parse mic mute")

  var badCRC = Array(makeDualSenseBluetoothReport(buttons0: 0x28))
  badCRC[77] ^= 0xFF
  do {
    _ = try parser.parse(data: Data(badCRC))
    require(false, "DualSense Bluetooth invalid CRC should throw")
  } catch let error as DualSenseParserError {
    require(error == .invalidBluetoothCRC, "DualSense Bluetooth invalid CRC should throw invalidBluetoothCRC")
  }
}

func runSwitchProTransportAndMappingCheck() throws {
  let parser = SwitchProParser()
  let bluetoothStartup = parser.hidStartupReports(transport: "Bluetooth")
  require(bluetoothStartup.map(\.reportID) == [0x01, 0x01], "Switch Pro Bluetooth should send subcommand startup reports")
  require(bluetoothStartup.map { $0.bytes[10] } == [0x03, 0x48], "Switch Pro Bluetooth startup should select full reports and enable IMU")
  require(parser.hidStartupReports(transport: nil).isEmpty, "Switch Pro unknown transport should skip USB startup reports")
  require(parser.hidStartupReports(transport: "USB").map(\.reportID) == [0x80, 0x80, 0x80, 0x80, 0x01, 0x01], "Switch Pro USB startup report IDs should match Linux init slice")

  let expectations: [(UInt32, Button)] = [
    (0x0000_0008, .b),
    (0x0000_0004, .a),
    (0x0000_0002, .y),
    (0x0000_0001, .x),
  ]
  for (mask, button) in expectations {
    let parser = SwitchProParser()
    _ = try parser.parse(data: makeSwitchProReport())
    let events = try parser.parse(data: makeSwitchProReport(buttons: mask))
    require(hasEvent(events, .buttonPressed(button)), "Switch Pro face-button mask \(mask) should map to \(button)")
  }

  let inputParser = SwitchProParser()
  _ = try inputParser.parse(data: makeSwitchProReport())
  let allPrimaryButtons: UInt32 = 0x00CA_3FCF
  let buttonEvents = try inputParser.parse(data: makeSwitchProReport(buttons: allPrimaryButtons))
  for expected in [Button.a, .b, .x, .y, .leftBumper, .rightBumper, .l2Digital, .r2Digital, .back, .start, .leftStick, .rightStick, .guide, .share] {
    require(hasEvent(buttonEvents, .buttonPressed(expected)), "Switch Pro primary input should press \(expected)")
  }
  require(hasEvent(buttonEvents, .dpadChanged(.northWest)), "Switch Pro should parse d-pad north-west")

  let stickParser = SwitchProParser()
  _ = try stickParser.parse(data: makeSwitchProReport())
  let stickEvents = try stickParser.parse(data: makeSwitchProReport(leftX: 4095, leftY: 0, rightX: 0, rightY: 4095))
  require(hasEvent(stickEvents, .leftStickChanged(x: 1.0, y: 1.0)), "Switch Pro should parse left 12-bit stick")
  require(hasEvent(stickEvents, .rightStickChanged(x: -1.0, y: -1.0)), "Switch Pro should parse right 12-bit stick")

  let startupReports = SwitchProParser().hidStartupReports()
  require(startupReports.map(\.reportID) == [0x80, 0x80, 0x80, 0x80, 0x01, 0x01], "Switch Pro USB startup report IDs should match Linux")
  require(startupReports.map { Array($0.bytes.prefix(2)) } == [[0x80, 0x02], [0x80, 0x03], [0x80, 0x02], [0x80, 0x04], [0x01, 0x00], [0x01, 0x01]], "Switch Pro USB startup reports should match Linux init prefixes")
  require(startupReports[4].bytes[10] == 0x03, "Switch Pro startup should set full report mode subcommand")
  require(startupReports[4].bytes[11] == 0x30, "Switch Pro startup should request full report mode 0x30")
  require(startupReports[5].bytes[10] == 0x48, "Switch Pro startup should enable IMU")
  require(startupReports[5].bytes[11] == 0x01, "Switch Pro startup should enable IMU data")
}

runProfileMetadataChecks()
try runSteamInputAndFeatureChecks()
try runSteamStatusFallbackCheck()
try runSteamWirelessConnectDisconnectCheck()
try runDS3InputChecks()
try runDS3TransportAndBluetoothCheck()
try runDualSenseUSBChecks()
try runDualSenseUnknownReportCheck()
try runDualSenseBluetoothCRCCheck()
try runSwitchProTransportAndMappingCheck()
print("PASS: macOS-14-compatible parser harness")
HARNESS_SWIFT

SWIFT_TARGET="${OJD_MACOS14_SWIFT_TARGET:-$(uname -m)-apple-macosx14.0}"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export MACOSX_DEPLOYMENT_TARGET=14.0
swift run \
  --disable-sandbox \
  --package-path "$HARNESS_DIR" \
  --scratch-path "$SCRATCH_DIR" \
  --cache-path "$CACHE_DIR" \
  --triple "$SWIFT_TARGET" \
  -Xswiftc -target \
  -Xswiftc "$SWIFT_TARGET" \
  OJDParserHarness
