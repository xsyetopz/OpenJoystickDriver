import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Subjects, inputs, and the binding pins every transcript relies on.
extension DriverLifecycleCharacterizationTests {
  static func model(_ vendorID: UInt16, _ productID: UInt16) -> ControllerModelID {
    ControllerModelID(vendorID: vendorID, productID: productID)
  }

  static let gipUSB = Subject(
    model: model(0x045E, 0x02D1),
    host: .usb,
    protocolID: .xboxGIP,
    variant: .usb,
    input: [gipAnnounceRequestingAcknowledgement]
  )
  static let gipKeepAliveDisabled = Subject(
    model: model(0x3285, 0x0634),
    host: .usb,
    protocolID: .xboxGIP,
    variant: .usb,
    input: [gipAnnounceRequestingAcknowledgement]
  )
  static let xidGamepad = Subject(
    model: model(0x0738, 0x4530),
    host: .usb,
    protocolID: .xboxXID,
    variant: .gamepad
  )
  static let xusbWired = Subject(
    model: model(0x045E, 0x028E),
    host: .usb,
    protocolID: .xboxXUSB,
    variant: .wired
  )
  static let xusbReceiver = Subject(
    model: model(0x045E, 0x0719),
    host: .usb,
    protocolID: .xboxXUSB,
    variant: .receiver,
    input: [
      ProtocolPacketFixtures.XUSBReceiver.padData(buttons: 1 << 12), Data([0x08, 0x80]),
      Data([0x08, 0x00]),
    ]
  )
  static let sixaxisUSB = Subject(
    model: model(0x054C, 0x0268),
    host: .usb,
    protocolID: .sonySixaxis,
    variant: .usb
  )
  static let sixaxisBluetooth = Subject(
    model: model(0x054C, 0x0268),
    host: .bluetoothClassic,
    protocolID: .sonySixaxis,
    variant: .bluetoothClassic
  )
  static let dualShock4USB = Subject(
    model: model(0x054C, 0x09CC),
    host: .usb,
    protocolID: .sonyDualShock4,
    variant: .usb,
    parameters: ProtocolParameters(motionCalibration: .factory),
    input: [dualShock4Report(timestamp: 1), dualShock4Report(timestamp: 2)]
  )
  static let dualShock4Bluetooth = Subject(
    model: model(0x054C, 0x09CC),
    host: .bluetoothClassic,
    protocolID: .sonyDualShock4,
    variant: .bluetoothClassic,
    parameters: ProtocolParameters(motionCalibration: .factory),
    input: [dualShock4Report(timestamp: 1), dualShock4Report(timestamp: 2)]
  )
  static let dualSenseUSB = Subject(
    model: model(0x054C, 0x0CE6),
    host: .usb,
    protocolID: .sonyDualSense,
    variant: .usb
  )
  static let dualSenseBluetooth = Subject(
    model: model(0x054C, 0x0CE6),
    host: .bluetoothClassic,
    protocolID: .sonyDualSense,
    variant: .bluetoothClassic
  )
  static let switchUSB = Subject(
    model: model(0x057E, 0x2009),
    host: .usb,
    protocolID: .nintendoSwitch1,
    variant: .usb
  )
  static let switchBluetooth = Subject(
    model: model(0x057E, 0x2009),
    host: .bluetoothClassic,
    protocolID: .nintendoSwitch1,
    variant: .bluetoothClassic
  )
  static let steamWired = Subject(
    model: model(0x28DE, 0x1102),
    host: .usb,
    protocolID: .valveSteamController,
    variant: .wired
  )
  static let steamDongle = Subject(
    model: model(0x28DE, 0x1142),
    host: .usb,
    protocolID: .valveSteamController,
    variant: .dongle,
    input: [
      ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02),
      ProtocolPacketFixtures.Steam.wirelessReport(status: 0x01),
    ],
    readyingInput: [ProtocolPacketFixtures.Steam.wirelessReport(status: 0x02)]
  )
  static let flydigi = Subject(
    model: model(0xD7D7, 0x0041),
    host: .usb,
    protocolID: .vendorFlydigi,
    variant: nil
  )
  static let ps3ThirdParty = Subject(
    model: model(0x06A3, 0xF622),
    host: .usb,
    protocolID: .vendorPS3ThirdParty,
    variant: nil,
    parameters: ProtocolParameters(hatSource: .dpadPressure)
  )
  static let reportLayout = Subject(
    model: model(0x2563, 0x0575),
    host: .usb,
    protocolID: .hidReportLayout,
    variant: nil
  )
  static let nvidiaShield = Subject(
    model: model(0x0955, 0x7210),
    host: .usb,
    protocolID: .vendorNVIDIAShield,
    variant: nil,
    parameters: ProtocolParameters(reportRevision: .shield2015)
  )
  static let gameSirUSB = Subject(
    model: model(0x3537, 0x1003),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .usb,
    input: gameSirUSBReadiness,
    readyingInput: gameSirUSBReadiness
  )
  static let gameSirEnhancedHID = Subject(
    model: model(0x3537, 0x100B),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .enhancedHID,
    parameters: ProtocolParameters(lightingMemory: .profileSlots),
    input: gameSirEnhancedReadiness,
    readyingInput: gameSirEnhancedReadiness
  )
  static let gameSirEnhancedHID8K = Subject(
    model: model(0x3537, 0x10C7),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .enhancedHID,
    parameters: ProtocolParameters(innerGrips: true),
    input: gameSirEnhancedReadiness,
    readyingInput: gameSirEnhancedReadiness
  )
  static let hidDescriptor = Subject(
    model: model(0x3537, 0x100A),
    host: .usb,
    protocolID: .hidDescriptor,
    variant: nil
  )

  /// Catalog rows outside ``subjects``.
  ///
  /// Only the output capability sweep uses them, so the transcripts over ``subjects`` stay
  /// unchanged.
  static let switchInputOnly = Subject(
    model: model(0x0F0D, 0x00C1),
    host: .usb,
    protocolID: .nintendoSwitchInputOnly,
    variant: .usb
  )
  static let tritonWired = Subject(
    model: model(0x28DE, 0x1302),
    host: .usb,
    protocolID: .valveSteamTriton,
    variant: .wired
  )
  static let tritonDongle = Subject(
    model: model(0x28DE, 0x1304),
    host: .usb,
    protocolID: .valveSteamTriton,
    variant: .dongle,
    readyingInput: [Data([0x79, 0x02])]
  )
  static let tritonBluetoothLE = Subject(
    model: model(0x28DE, 0x1303),
    host: .bluetoothLE,
    protocolID: .valveSteamTriton,
    variant: .bluetoothLE
  )
  static let steamDeck = Subject(
    model: model(0x28DE, 0x1205),
    host: .usb,
    protocolID: .valveSteamDeck,
    variant: nil
  )
  static let steamBluetoothLE = Subject(
    model: model(0x28DE, 0x1106),
    host: .bluetoothLE,
    protocolID: .valveSteamController,
    variant: .bluetoothLE
  )
  static let switch2USB = Subject(
    model: model(0x057E, 0x2069),
    host: .usb,
    protocolID: .nintendoSwitch2,
    variant: .usb
  )
  static let switch2BluetoothLE = Subject(
    model: model(0x057E, 0x2069),
    host: .bluetoothLE,
    protocolID: .nintendoSwitch2,
    variant: .bluetoothLE
  )
  static let inputOnlyUSB = Subject(
    model: model(0x0E6F, 0x0180),
    host: .usb,
    protocolID: .nintendoSwitchInputOnly,
    variant: .usb
  )
  static let inputOnlyBluetooth = Subject(
    model: model(0x0E6F, 0x0180),
    host: .bluetoothClassic,
    protocolID: .nintendoSwitchInputOnly,
    variant: .bluetoothClassic
  )
  static let sweepSubjects = [
    tritonWired, tritonDongle, tritonBluetoothLE, steamDeck, steamBluetoothLE, switch2USB,
    switch2BluetoothLE, inputOnlyUSB, inputOnlyBluetooth,
  ]

  static let subjects = [
    gipUSB, gipKeepAliveDisabled, xidGamepad, xusbWired, xusbReceiver, sixaxisUSB, sixaxisBluetooth,
    dualShock4USB, dualShock4Bluetooth, dualSenseUSB, dualSenseBluetooth, switchUSB,
    switchBluetooth, steamWired, steamDongle, flydigi, ps3ThirdParty, nvidiaShield, gameSirUSB,
    gameSirEnhancedHID, gameSirEnhancedHID8K, hidDescriptor, reportLayout,
  ]

  @Test
  func everySubjectBindsItsFamilyAndVariantThroughTheRegistry() throws {
    for subject in Self.subjects {
      let record = try #require(Self.registry.record(for: subject.model))
      let device = PhysicalDevice(
        vendorID: subject.model.vendorID,
        productID: subject.model.productID,
        interfaces: record.usesRawUSB ? nil : [gamepadHIDInterface(host: subject.host)]
      )
      let backend: DeviceAccessBackend = record.usesRawUSB ? .rawUSB : .hid
      guard case .bound(let binding) = Self.registry.classify(device, backend: backend) else {
        Issue.record("\(subject.model) did not bind")
        continue
      }
      #expect(binding.protocolID == subject.protocolID, "\(subject.model)")
      #expect(binding.variant == subject.variant, "\(subject.model)")
      #expect(record.parameters == subject.parameters, "\(subject.model)")
    }
    let gip = try #require(Self.registry.record(for: Self.gipUSB.model))
    #expect(gip.gipKeepAlivePolicy == .enabled)
    #expect(gip.gipStartupPackets.isEmpty)
    let disabled = try #require(Self.registry.record(for: Self.gipKeepAliveDisabled.model))
    #expect(disabled.gipKeepAlivePolicy == .disabled)
    #expect(disabled.gipStartupPackets.isEmpty)
  }

  // MARK: - Inputs

  /// Razer Wolverine TE announce captured on hardware, with the acknowledge option set.
  static let gipAnnounceRequestingAcknowledgement =
    Data([0x02, 0x30, 0x01, 0x1C, 0x59, 0xE9, 0x51, 0x77, 0xCF, 0x39, 0x00, 0x00])
    + Data([0x32, 0x15, 0x15, 0x0A, 0x01, 0x00, 0x01, 0x00, 0x40, 0x01, 0x02, 0x00])
    + Data([0x01, 0x00, 0x01, 0x00, 0x01, 0x00, 0x01, 0x00])

  static func dualShock4Report(timestamp: UInt8) -> Data {
    var report = [UInt8](repeating: 0, count: 64)
    report.replaceSubrange(0..<6, with: [0x01, 0x80, 0x80, 0x80, 0x80, 0x08])
    report[10] = timestamp
    return Data(report)
  }

  static let gameSirUSBReadiness: [Data] = {
    var slot = [UInt8](repeating: 0, count: 64)
    slot.replaceSubrange(0..<7, with: [0x10, 0x05, 0x20, 0x00, 0x00, 0x01, 0x02])
    var telemetry = [UInt8](repeating: 0, count: 64)
    telemetry[0] = 0x10
    telemetry[3] = 0x3C
    telemetry[4] = 0xE0
    telemetry[32] = 1
    telemetry[33] = 73
    return [Data(slot), Data(telemetry)]
  }()

  static let gameSirEnhancedReadiness: [Data] = {
    var slot = [UInt8](repeating: 0, count: 64)
    slot.replaceSubrange(0..<7, with: [0x10, 0x05, 0x20, 0x00, 0x00, 0x01, 0x02])
    var report = [UInt8](repeating: 0, count: 64)
    report.replaceSubrange(0..<5, with: [0x12, 0x80, 0x80, 0x80, 0x80])
    report[35] = 1
    report[36] = 84
    return [Data(slot), Data(report)]
  }()

  /// A factory motion-calibration reply shaped like the request; 41-byte replies carry the
  /// Bluetooth feature CRC.
  ///
  /// DualShock 4 Bluetooth groups the gyro endpoints.
  func sonyFactoryReply(for request: PhysicalHIDFeatureReadRequest, groupedEndpoints: Bool) -> Data
  {
    var data = [UInt8](repeating: 0, count: request.length)
    data[0] = request.reportID
    func write(_ value: Int16, at offset: Int) {
      let raw = UInt16(bitPattern: value)
      data[offset] = UInt8(truncatingIfNeeded: raw)
      data[offset + 1] = UInt8(truncatingIfNeeded: raw >> 8)
    }
    for (index, bias) in [Int16(20), -30, 40].enumerated() {
      let endpoint = Int16(8000 + index * 2000)
      write(bias, at: 1 + index * 2)
      write(endpoint, at: groupedEndpoints ? 7 + index * 2 : 7 + index * 4)
      write(-endpoint, at: groupedEndpoints ? 13 + index * 2 : 9 + index * 4)
      write(8292, at: 23 + index * 4)
      write(-8092, at: 25 + index * 4)
    }
    write(500, at: 19)
    write(500, at: 21)
    guard request.length == 41 else { return Data(data) }
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in [UInt8(0xA3)] + data.prefix(37) {
      crc ^= UInt32(byte)
      for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xEDB8_8320 }
    }
    crc = ~crc
    for index in 0..<4 { data[37 + index] = UInt8(truncatingIfNeeded: crc >> (8 * index)) }
    return Data(data)
  }
}
