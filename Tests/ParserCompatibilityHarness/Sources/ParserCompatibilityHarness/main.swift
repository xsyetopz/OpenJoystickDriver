import Foundation
import OpenJoystickDriverKit
import ProtocolPacketFixtures

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

/// A stick position from normalized axes whose Y points down.
func stick(_ x: Float, _ y: Float) -> StickPosition {
  StickPosition(x: BipolarValue(normalized: x), y: BipolarValue(normalized: y))
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

func catalogRecord(_ model: ControllerModelID) -> DeviceRuntimeProfile {
  guard let record = ProtocolDriverRegistry().record(for: model) else {
    fputs("FAIL: \(model) should have a catalog record\n", stderr)
    exit(1)
  }
  return record
}

func runProfileMetadataChecks() {
  let ds3Profile = catalogRecord(ControllerModelID(vendorID: 1356, productID: 616))
  require(
    ds3Profile.physicalProtocolID == .sonySixaxis && ds3Profile.physicalProtocolVariant == nil,
    "DS3 profile should bind Sixaxis"
  )
  require(
    ds3Profile.parameters.isEmpty,
    "DS3 profile should not advertise unimplemented sensors or battery status"
  )

  for id in [
    ControllerModelID(vendorID: 1356, productID: 3302),
    ControllerModelID(vendorID: 1356, productID: 3570),
  ] {
    let profile = catalogRecord(id)
    require(
      profile.physicalProtocolID == .sonyDualSense && profile.physicalProtocolVariant == nil,
      "DualSense profile should bind"
    )
    require(profile.parameters.isEmpty, "DualSense profile should declare no parameters")
    require(
      profile.capabilityDelta.presentControls
        == (id.productID == 3570
          ? [.leftPaddle1, .rightPaddle1, .auxiliary1, .auxiliary2] : []),
      "Only the DualSense Edge profile should declare its function buttons and paddles"
    )
  }

  let steamWiredProfile = catalogRecord(ControllerModelID(vendorID: 10462, productID: 4354))
  require(
    steamWiredProfile.physicalProtocolID == .valveSteamController
      && steamWiredProfile.physicalProtocolVariant == .wired,
    "Steam wired should bind the wired variant"
  )
  require(steamWiredProfile.parameters.isEmpty, "Steam wired profile should declare no parameters")

  let steamWirelessProfile = catalogRecord(ControllerModelID(vendorID: 10462, productID: 4418))
  require(
    steamWirelessProfile.physicalProtocolID == .valveSteamController
      && steamWirelessProfile.physicalProtocolVariant == .dongle,
    "Steam wireless receiver should bind the dongle variant"
  )
  require(
    steamWirelessProfile.parameters.isEmpty,
    "Steam dongle profile should declare no parameters"
  )

  let switchProfile = catalogRecord(ControllerModelID(vendorID: 1406, productID: 8201))
  require(
    switchProfile.physicalProtocolID == .nintendoSwitch1
      && switchProfile.physicalProtocolVariant == nil,
    "Switch Pro profile should bind Switch 1"
  )
  require(switchProfile.parameters.isEmpty, "Switch Pro profile should select the Pro layout")
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
    Control.south, .east, .west, .north, .leftShoulder, .rightShoulder, .back,
    .guide, .start, .leftStickClick, .rightTrackpadClick,
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
  require(
    startup.map(\.reportID) == [0, 0, 0],
    "Steam lizard startup reports should use report ID 0"
  )
  require(
    startup.map { $0.bytes.count } == [64, 64, 64],
    "Steam lizard startup reports should be 64 bytes"
  )
  require(startup[0].bytes[0] == 0x81, "Steam startup should clear digital mappings")
  require(startup[1].bytes[0] == 0x8E, "Steam startup should load default settings")
  require(
    Array(startup[2].bytes.prefix(14)) == ProtocolPacketFixtures.Steam.startupSettingsPrefix,
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
