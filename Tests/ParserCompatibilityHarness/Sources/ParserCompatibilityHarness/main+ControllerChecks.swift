import Foundation
import ProtocolPacketFixtures
import OpenJoystickDriverKit

func runSteamStatusFallbackCheck() throws {
  let parser = SteamControllerDriver(isWirelessReceiver: true)
  let statusEvents = try parse(parser, ProtocolPacketFixtures.Steam.statusReport)
  require(statusEvents == nil, "Steam status report should not emit input events")
  require(
    parser.consumeInputConnectionStateChange() == .connected,
    "Steam status report should mark receiver connected"
  )
  let inputEvents = try parse(
    parser,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
  )
  require(
    inputEvents?.pressed.contains(.faceSouth) == true,
    "Steam input after status fallback should parse A press"
  )
}

func runSteamWirelessConnectDisconnectCheck() throws {
  let parser = SteamControllerDriver(isWirelessReceiver: true)
  require(
    parser.sessionPlan.requiresInputConnectionBeforeOutput,
    "Steam wireless receiver should gate output"
  )

  let preConnectEvents = try parse(
    parser,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
  )
  require(preConnectEvents == nil, "Steam wireless input before logical connect should be ignored")

  let connectEvents = try parse(parser, ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02))
  require(connectEvents == nil, "Steam wireless connect report should not emit input")
  require(
    parser.consumeInputConnectionStateChange() == .connected,
    "Steam wireless connect report should emit connected lifecycle"
  )
  require(
    parser.consumeInputConnectionStateChange() == nil,
    "Steam wireless lifecycle should be consumed once"
  )

  let inputEvents = try parse(
    parser,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
  )
  require(
    inputEvents?.pressed.contains(.faceSouth) == true,
    "Steam wireless input after connect should parse A press"
  )

  let disconnectEvents = try parse(
    parser,
    ProtocolPacketFixtures.Steam.wirelessReport(status: 0x01)
  )
  require(disconnectEvents == nil, "Steam wireless disconnect report should not emit input")
  require(
    parser.consumeInputConnectionStateChange() == .disconnected,
    "Steam wireless disconnect report should emit disconnected lifecycle"
  )

  let postDisconnectEvents = try parse(
    parser,
    ProtocolPacketFixtures.Steam.inputReport(buttons: (0x80, 0, 0))
  )
  require(postDisconnectEvents == nil, "Steam wireless input after disconnect should be ignored")
}

func runDS3InputChecks() throws {
  let parser = SixaxisDriver()
  _ = try parse(parser, ProtocolPacketFixtures.DS3.inputReport())
  let buttonEvents = try parse(
    parser,
    ProtocolPacketFixtures.DS3.inputReport(buttons: (0x3F, 0xFF, true))
  )
  for expected in [
    ControlID.view, .leftStickClick, .rightStickClick, .menu, .leftTriggerButton,
    .rightTriggerButton, .leftShoulder, .rightShoulder, .faceNorth, .faceEast, .faceSouth,
    .faceWest, .guide,
  ] {
    require(
      buttonEvents?.pressed.contains(expected) == true,
      "DS3 primary input should press \(expected)"
    )
  }
  require(buttonEvents?.hat == .northEast, "DS3 should parse d-pad north-east")

  let axisParser = SixaxisDriver()
  _ = try parse(axisParser, ProtocolPacketFixtures.DS3.inputReport())
  let axisEvents = try parse(
    axisParser,
    ProtocolPacketFixtures.DS3.inputReport(sticks: ((255, 0), (0, 255)), triggers: (255, 128))
  )
  require(axisEvents?.leftStick == stick(1.0, -1.0), "DS3 should parse left stick")
  require(axisEvents?.rightStick == stick(-1.0, 1.0), "DS3 should parse right stick")
  require(axisEvents?.leftTrigger == trigger(1.0), "DS3 should parse left analog trigger")
  require(
    axisEvents?.rightTrigger == trigger(128.0 / 255.0),
    "DS3 should parse right analog trigger"
  )
}

func runDS3TransportAndBluetoothCheck() throws {
  let parser = SixaxisDriver()
  let bluetooth = SixaxisDriver(isBluetooth: true)
  require(
    parser.startupFeatureReads() == [
      PhysicalHIDFeatureReadRequest(reportID: 0xF2, length: 17),
      PhysicalHIDFeatureReadRequest(reportID: 0xF5, length: 8),
    ],
    "DS3 USB startup reads should match Linux"
  )
  require(
    bluetooth.startupFeatureReads().isEmpty,
    "DS3 Bluetooth should not send USB feature reads"
  )
  require(parser.activationWrites().isEmpty, "DS3 USB should not send Bluetooth feature report")
  require(
    bluetooth.activationWrites().isEmpty,
    "DS3 Bluetooth enable report should come from the controller record"
  )
  var bogus = Array(
    ProtocolPacketFixtures.DS3.inputReport(
      buttons: (0x10, 0x40, false),
      sticks: ((255, 128), (128, 128)),
      triggers: (255, 0)
    )
  )
  bogus[1] = 0xFF
  let events = try parse(parser, Data(bogus))
  require(events == nil, "DS3 bogus Bluetooth status report should be ignored")
}

func runDualSenseUSBChecks() throws {
  let parser = DualSenseDriver()
  _ = try parse(parser, ProtocolPacketFixtures.DualSense.usbInputReport())
  let events = try parse(
    parser,
    ProtocolPacketFixtures.DualSense.usbInputReport(
      sticks: ((255, 0), (0, 255)),
      triggers: (255, 128),
      buttons: (0x28, 0x30, 0x03)
    )
  )
  require(events?.leftStick == stick(1.0, -1.0), "DualSense USB should parse left stick")
  require(events?.rightStick == stick(-1.0, 1.0), "DualSense USB should parse right stick")
  require(events?.leftTrigger == trigger(1.0), "DualSense USB should parse left trigger")
  require(
    events?.rightTrigger == trigger(128.0 / 255.0),
    "DualSense USB should parse right trigger"
  )
  for expected in [ControlID.faceSouth, .view, .menu, .guide, .touchpadClick] {
    require(events?.pressed.contains(expected) == true, "DualSense USB should press \(expected)")
  }

  let micParser = DualSenseDriver()
  _ = try parse(micParser, ProtocolPacketFixtures.DualSense.usbInputReport())
  let micEvents = try parse(
    micParser,
    ProtocolPacketFixtures.DualSense.usbInputReport(buttons: (0x08, 0, 0x04))
  )
  require(micEvents?.pressed.contains(.microphone) == true, "DualSense USB should parse mic mute")
}

func runDualSenseUnknownReportCheck() throws {
  let parser = DualSenseDriver()
  var report = [UInt8](repeating: 0, count: 64)
  report[0] = 0x02
  report[1] = 255
  report[2] = 0
  report[5] = 255
  report[8] = 0x28
  let events = try parse(parser, Data(report))
  require(events == nil, "DualSense unknown report IDs should be ignored")
}

func runDualSenseBluetoothCRCCheck() throws {
  let parser = DualSenseDriver()
  _ = try parse(parser, ProtocolPacketFixtures.DualSense.bluetoothInputReport())
  let events = try parse(
    parser,
    ProtocolPacketFixtures.DualSense.bluetoothInputReport(
      sticks: ((255, 0), (0, 255)),
      triggers: (255, 128),
      buttons: (0x28, 0x30, 0x07)
    )
  )
  require(events?.leftStick == stick(1.0, -1.0), "DualSense Bluetooth should parse left stick")
  require(events?.rightStick == stick(-1.0, 1.0), "DualSense Bluetooth should parse right stick")
  require(events?.leftTrigger == trigger(1.0), "DualSense Bluetooth should parse left trigger")
  require(
    events?.rightTrigger == trigger(128.0 / 255.0),
    "DualSense Bluetooth should parse right trigger"
  )
  require(events?.pressed.contains(.faceSouth) == true, "DualSense Bluetooth should parse Cross")
  require(events?.pressed.contains(.view) == true, "DualSense Bluetooth should parse Create/Share")
  require(events?.pressed.contains(.menu) == true, "DualSense Bluetooth should parse Options")
  require(events?.pressed.contains(.guide) == true, "DualSense Bluetooth should parse PS")
  require(
    events?.pressed.contains(.touchpadClick) == true,
    "DualSense Bluetooth should parse touchpad"
  )
  require(
    events?.pressed.contains(.microphone) == true,
    "DualSense Bluetooth should parse mic mute"
  )

  var badCRC = Array(ProtocolPacketFixtures.DualSense.bluetoothInputReport(buttons: (0x28, 0, 0)))
  badCRC[77] ^= 0xFF
  do {
    _ = try parse(parser, Data(badCRC))
    require(false, "DualSense Bluetooth invalid CRC should throw")
  } catch let error as DualSenseDriverError {
    require(
      error == .invalidBluetoothCRC,
      "DualSense Bluetooth invalid CRC should throw invalidBluetoothCRC"
    )
  }
}

func runSwitchProTransportAndMappingCheck() throws {
  let bluetoothStartup = hidReports(Switch1Driver(isBluetooth: true).startupWrites())
  require(
    bluetoothStartup.map(\.reportID) == ProtocolPacketFixtures.SwitchPro.bluetoothStartupReportIDs,
    "Switch Pro Bluetooth should send subcommand startup reports"
  )
  require(
    bluetoothStartup.map { $0.bytes[10] }
      == ProtocolPacketFixtures.SwitchPro.bluetoothStartupSubcommands,
    "Switch Pro Bluetooth startup should select full reports, enable IMU and rumble, "
      + "and request calibration"
  )
  require(
    hidReports(Switch1Driver().startupWrites()).map(\.reportID)
      == ProtocolPacketFixtures.SwitchPro.usbStartupReportIDs,
    "Switch Pro USB startup report IDs should match Linux init slice"
  )

  let expectations: [(UInt32, ControlID)] = [
    (0x0000_0008, .faceEast), (0x0000_0004, .faceSouth), (0x0000_0002, .faceNorth),
    (0x0000_0001, .faceWest),
  ]
  for (mask, button) in expectations {
    let parser = Switch1Driver()
    _ = try parse(parser, ProtocolPacketFixtures.SwitchPro.inputReport())
    let events = try parse(parser, ProtocolPacketFixtures.SwitchPro.inputReport(buttons: mask))
    require(
      events?.pressed.contains(button) == true,
      "Switch Pro face-button mask \(mask) should map to \(button)"
    )
  }

  let inputParser = Switch1Driver()
  _ = try parse(inputParser, ProtocolPacketFixtures.SwitchPro.inputReport())
  let allPrimaryButtons: UInt32 = 0x00CA_3FCF
  let buttonEvents = try parse(
    inputParser,
    ProtocolPacketFixtures.SwitchPro.inputReport(buttons: allPrimaryButtons)
  )
  for expected in [
    ControlID.faceSouth, .faceEast, .faceWest, .faceNorth, .leftShoulder, .rightShoulder,
    .leftTriggerButton, .rightTriggerButton, .view, .menu, .leftStickClick, .rightStickClick,
    .guide, .capture,
  ] {
    require(
      buttonEvents?.pressed.contains(expected) == true,
      "Switch Pro primary input should press \(expected)"
    )
  }
  require(buttonEvents?.hat == .northWest, "Switch Pro should parse d-pad north-west")

  let stickParser = Switch1Driver()
  _ = try parse(stickParser, ProtocolPacketFixtures.SwitchPro.inputReport())
  let stickEvents = try parse(
    stickParser,
    ProtocolPacketFixtures.SwitchPro.inputReport(sticks: ((4095, 0), (0, 4095)))
  )
  require(stickEvents?.leftStick == stick(1.0, 1.0), "Switch Pro should parse left 12-bit stick")
  require(
    stickEvents?.rightStick == stick(-1.0, -1.0),
    "Switch Pro should parse right 12-bit stick"
  )

  let startupReports = hidReports(Switch1Driver().startupWrites())
  require(
    startupReports.map(\.reportID) == ProtocolPacketFixtures.SwitchPro.usbStartupReportIDs,
    "Switch Pro USB startup report IDs should match Linux"
  )
  require(
    startupReports.map { Array($0.bytes.prefix(2)) } == [
      [0x80, 0x02], [0x80, 0x03], [0x80, 0x02], [0x80, 0x04], [0x01, 0x00], [0x01, 0x01],
      [0x01, 0x02], [0x01, 0x03], [0x01, 0x04],
    ],
    "Switch Pro USB startup reports should match Linux init prefixes"
  )
  require(
    startupReports[4].bytes[10] == 0x03,
    "Switch Pro startup should set full report mode subcommand"
  )
  require(
    startupReports[4].bytes[11] == 0x30,
    "Switch Pro startup should request full report mode 0x30"
  )
  require(startupReports[5].bytes[10] == 0x40, "Switch Pro startup should enable IMU")
  require(
    startupReports[6].bytes[10] == 0x48 && startupReports[6].bytes[11] == 1,
    "Switch Pro startup should enable rumble"
  )
  require(startupReports[5].bytes[11] == 0x01, "Switch Pro startup should enable IMU data")
}
