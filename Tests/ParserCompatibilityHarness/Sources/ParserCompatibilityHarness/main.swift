import Foundation
import ProtocolPacketFixtures
import OpenJoystickDriverKit

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
  if !condition() {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

/// The state one report leaves, or nil for a frame without input.
func parse(_ parser: any PhysicalProtocolDriver, _ report: Data) throws -> ControllerState? {
  try parser.parse(report: report, receivedAt: MonotonicTimestamp(nanoseconds: 0))?.state
}

/// A stick position from normalized axes whose Y points down, the report frame.
func stick(_ x: Float, _ yDown: Float) -> StickPosition {
  StickPosition(x: BipolarValue(normalized: x), y: BipolarValue(normalized: -yDown))
}

func trigger(_ value: Float) -> UnipolarValue { UnipolarValue(normalized: value) }

/// The HID reports driver writes carry, in order.
func hidReports(_ writes: [PhysicalOutputWrite]) -> [PhysicalHIDOutputReport] {
  writes.compactMap { write in
    switch write {
    case .usb: nil
    case .hidOutput(let report), .hidFeature(let report): report
    }
  }
}

func catalogRecord(_ identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
  guard let record = ProtocolDriverRegistry().record(for: identifier) else {
    fputs("FAIL: \(identifier) should have a catalog record\n", stderr)
    exit(1)
  }
  return record
}

func runProfileMetadataChecks() {
  let ds3Profile = catalogRecord(DeviceIdentifier(vendorID: 1356, productID: 616))
  require(
    ds3Profile.physicalProtocolID == .sonySixaxis && ds3Profile.physicalProtocolVariant == nil,
    "DS3 profile should bind Sixaxis"
  )
  require(
    ds3Profile.quirks.isEmpty,
    "DS3 profile should not advertise unimplemented sensors or battery status"
  )

  for id in [
    DeviceIdentifier(vendorID: 1356, productID: 3302),
    DeviceIdentifier(vendorID: 1356, productID: 3570),
  ] {
    let profile = catalogRecord(id)
    require(
      profile.physicalProtocolID == .sonyDualSense && profile.physicalProtocolVariant == nil,
      "DualSense profile should bind"
    )
    require(profile.quirks.isEmpty, "DualSense profile should declare no quirks")
    require(
      profile.capabilityDelta.presentControls
        == (id.controllerIdentity.productID == 3570
          ? [.paddleLeft1, .paddleRight1, .auxiliary1, .auxiliary2] : []),
      "Only the DualSense Edge profile should declare its function buttons and paddles"
    )
  }

  let steamWiredProfile = catalogRecord(DeviceIdentifier(vendorID: 10462, productID: 4354))
  require(
    steamWiredProfile.physicalProtocolID == .valveSteamController
      && steamWiredProfile.physicalProtocolVariant == .wired,
    "Steam wired should bind the wired variant"
  )
  require(steamWiredProfile.quirks.isEmpty, "Steam wired profile should declare no quirks")

  let steamWirelessProfile = catalogRecord(DeviceIdentifier(vendorID: 10462, productID: 4418))
  require(
    steamWirelessProfile.physicalProtocolID == .valveSteamController
      && steamWirelessProfile.physicalProtocolVariant == .dongle,
    "Steam wireless receiver should bind the dongle variant"
  )
  require(steamWirelessProfile.quirks.isEmpty, "Steam dongle profile should declare no quirks")

  let switchProfile = catalogRecord(DeviceIdentifier(vendorID: 1406, productID: 8201))
  require(
    switchProfile.physicalProtocolID == .nintendoSwitch1
      && switchProfile.physicalProtocolVariant == nil,
    "Switch Pro profile should bind Switch 1"
  )
  require(switchProfile.quirks.isEmpty, "Switch Pro profile should select the Pro layout")
}

func runSteamInputAndFeatureChecks() throws {
  let parser = SteamControllerDriver()
  _ = try parse(parser, ProtocolPacketFixtures.Steam.inputReport())
  let events = try parse(
    parser,
    ProtocolPacketFixtures.Steam.inputReport(
      buttons: (0xFC, 0x70, 0x44),
      triggers: (255, 128),
      left: (32767, -32767),
      rightPad: (-32767, 32767)
    )
  )
  for expected in [
    ControlID.faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder, .view,
    .guide, .menu, .leftStickClick, .rightTrackpadClick,
  ] {
    require(
      events?.pressed.contains(expected) == true,
      "Steam primary input should press \(expected)"
    )
  }
  require(events?.leftTrigger == trigger(1.0), "Steam should parse left trigger")
  require(events?.rightTrigger == trigger(128.0 / 255.0), "Steam should parse right trigger")
  require(events?.leftStick == stick(1.0, 1.0), "Steam should parse left stick")
  require(events?.rightStick == stick(-1.0, -1.0), "Steam should parse right pad as right stick")

  let leftPadOnly = SteamControllerDriver()
  _ = try parse(leftPadOnly, ProtocolPacketFixtures.Steam.inputReport())
  let leftPadOnlyEvents = try parse(
    leftPadOnly,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0, 0x08), left: (32767, -32767))
  )
  require(
    leftPadOnlyEvents?.leftStick != stick(1.0, 1.0),
    "Steam left-pad-only coordinates should not create left-stick motion"
  )

  let leftPadAndJoy = SteamControllerDriver()
  _ = try parse(leftPadAndJoy, ProtocolPacketFixtures.Steam.inputReport())
  let leftPadAndJoyEvents = try parse(
    leftPadAndJoy,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0, 0x88), left: (32767, -32767))
  )
  require(
    leftPadAndJoyEvents?.leftStick != stick(1.0, 1.0),
    "Steam interleaved pad coordinates must not overwrite the left stick"
  )

  let dpad = SteamControllerDriver()
  _ = try parse(dpad, ProtocolPacketFixtures.Steam.inputReport())
  let upEvents = try parse(dpad, ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x01, 0)))
  let rightEvents = try parse(dpad, ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x02, 0)))
  let downEvents = try parse(dpad, ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x08, 0)))
  let leftEvents = try parse(dpad, ProtocolPacketFixtures.Steam.inputReport(buttons: (0, 0x04, 0)))
  require(upEvents?.hat == .north, "Steam should parse d-pad north")
  require(rightEvents?.hat == .east, "Steam should parse d-pad east")
  require(downEvents?.hat == .south, "Steam should parse d-pad south")
  require(leftEvents?.hat == .west, "Steam should parse d-pad west")

  let featureParser = SteamControllerDriver()
  let startup = hidReports(featureParser.activationWrites())
  require(startup.map(\.reportID) == [0, 0], "Steam lizard startup reports should use report ID 0")
  require(
    startup.map { $0.bytes.count } == [64, 64],
    "Steam lizard startup reports should be 64 bytes"
  )
  require(startup[0].bytes[0] == 0x81, "Steam startup should clear digital mappings")
  require(
    Array(startup[1].bytes.prefix(11)) == ProtocolPacketFixtures.Steam.startupSettingsPrefix,
    "Steam startup should disable trackpad mouse modes and request raw IMU data"
  )
  let shutdown = hidReports(featureParser.deactivationWrites())
  require(shutdown.map(\.reportID) == [0, 0], "Steam shutdown reports should use report ID 0")
  require(shutdown[0].bytes[0] == 0x85, "Steam shutdown should restore digital mappings")
  require(shutdown[1].bytes[0] == 0x8E, "Steam shutdown should load default settings")
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
try runXIDInputChecks()
try runDualShock4RecordQuirkChecks()
try runShieldRecordQuirkChecks()
runStickDeadzoneTuningCheck()
print("PASS: macOS-14-compatible parser harness")
