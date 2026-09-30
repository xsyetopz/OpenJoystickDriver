import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

// Subjects, inputs, and the binding pins every transcript relies on.
extension DriverLifecycleCharacterizationTests {
  static func identifier(_ vendorID: UInt16, _ productID: UInt16) -> DeviceIdentifier {
    DeviceIdentifier(vendorID: vendorID, productID: productID)
  }

  static let gipUSB = Subject(
    identifier: identifier(0x045E, 0x02D1),
    host: .usb,
    protocolID: .xboxGIP,
    variant: .usb,
    input: [gipAnnounceRequestingAcknowledgement]
  )
  static let gipKeepAliveDisabled = Subject(
    identifier: identifier(0x3285, 0x0634),
    host: .usb,
    protocolID: .xboxGIP,
    variant: .usb,
    input: [gipAnnounceRequestingAcknowledgement]
  )
  static let xidGamepad = Subject(
    identifier: identifier(0x0738, 0x4530),
    host: .usb,
    protocolID: .xboxXID,
    variant: .gamepad
  )
  static let xusbWired = Subject(
    identifier: identifier(0x045E, 0x028E),
    host: .usb,
    protocolID: .xboxXUSB,
    variant: .wired
  )
  static let xusbReceiver = Subject(
    identifier: identifier(0x045E, 0x0719),
    host: .usb,
    protocolID: .xboxXUSB,
    variant: .receiver,
    input: [
      ProtocolPacketFixtures.XUSBReceiver.padData(buttons: 1 << 12), Data([0x08, 0x80]),
      Data([0x08, 0x00]),
    ]
  )
  static let sixaxisUSB = Subject(
    identifier: identifier(0x054C, 0x0268),
    host: .usb,
    protocolID: .sonySixaxis,
    variant: .usb
  )
  static let sixaxisBluetooth = Subject(
    identifier: identifier(0x054C, 0x0268),
    host: .bluetoothClassic,
    protocolID: .sonySixaxis,
    variant: .bluetoothClassic
  )
  static let dualShock4USB = Subject(
    identifier: identifier(0x054C, 0x09CC),
    host: .usb,
    protocolID: .sonyDualShock4,
    variant: .usb,
    input: [dualShock4Report(timestamp: 1), dualShock4Report(timestamp: 2)]
  )
  static let dualShock4Bluetooth = Subject(
    identifier: identifier(0x054C, 0x09CC),
    host: .bluetoothClassic,
    protocolID: .sonyDualShock4,
    variant: .bluetoothClassic,
    input: [dualShock4Report(timestamp: 1), dualShock4Report(timestamp: 2)]
  )
  static let dualSenseUSB = Subject(
    identifier: identifier(0x054C, 0x0CE6),
    host: .usb,
    protocolID: .sonyDualSense,
    variant: .usb
  )
  static let dualSenseBluetooth = Subject(
    identifier: identifier(0x054C, 0x0CE6),
    host: .bluetoothClassic,
    protocolID: .sonyDualSense,
    variant: .bluetoothClassic
  )
  static let switchUSB = Subject(
    identifier: identifier(0x057E, 0x2009),
    host: .usb,
    protocolID: .nintendoSwitch1,
    variant: .usb
  )
  static let switchBluetooth = Subject(
    identifier: identifier(0x057E, 0x2009),
    host: .bluetoothClassic,
    protocolID: .nintendoSwitch1,
    variant: .bluetoothClassic
  )
  static let steamWired = Subject(
    identifier: identifier(0x28DE, 0x1102),
    host: .usb,
    protocolID: .valveSteamController,
    variant: .wired
  )
  static let steamDongle = Subject(
    identifier: identifier(0x28DE, 0x1142),
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
    identifier: identifier(0xD7D7, 0x0041),
    host: .usb,
    protocolID: .vendorFlydigi,
    variant: nil
  )
  static let gameSirUSB = Subject(
    identifier: identifier(0x3537, 0x1003),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .usb,
    input: gameSirUSBReadiness,
    readyingInput: gameSirUSBReadiness
  )
  static let gameSirEnhancedHID = Subject(
    identifier: identifier(0x3537, 0x100B),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .enhancedHID,
    quirks: [.lightingSlots],
    input: gameSirEnhancedReadiness,
    readyingInput: gameSirEnhancedReadiness
  )
  static let gameSirEnhancedHID8K = Subject(
    identifier: identifier(0x3537, 0x10C7),
    host: .usb,
    protocolID: .vendorGameSir,
    variant: .enhancedHID,
    quirks: [.innerGrips],
    input: gameSirEnhancedReadiness,
    readyingInput: gameSirEnhancedReadiness
  )
  static let hidDescriptor = Subject(
    identifier: identifier(0x3537, 0x100A),
    host: .usb,
    protocolID: .hidDescriptor,
    variant: nil
  )

  static let byteLayout = Subject(
    identifier: identifier(0x2563, 0x0575),
    host: .usb,
    protocolID: .genericByteLayout,
    variant: nil
  )

  static let subjects = [
    gipUSB, gipKeepAliveDisabled, xidGamepad, xusbWired, xusbReceiver, sixaxisUSB, sixaxisBluetooth,
    dualShock4USB, dualShock4Bluetooth, dualSenseUSB, dualSenseBluetooth, switchUSB,
    switchBluetooth, steamWired, steamDongle, flydigi, gameSirUSB, gameSirEnhancedHID,
    gameSirEnhancedHID8K, hidDescriptor, byteLayout,
  ]

  @Test
  func everySubjectBindsItsFamilyAndVariantThroughTheRegistry() throws {
    for subject in Self.subjects {
      let record = try #require(Self.registry.record(for: subject.identifier))
      let device = PhysicalDevice(
        vendorID: subject.identifier.controllerIdentity.vendorID,
        productID: subject.identifier.controllerIdentity.productID,
        interfaces: record.usesRawUSB ? nil : [gamepadHIDInterface(host: subject.host)]
      )
      let backend: DeviceAccessBackend = record.usesRawUSB ? .ioUSBHost : .ioHID
      guard case .bound(let binding) = Self.registry.classify(device, backend: backend) else {
        Issue.record("\(subject.identifier) did not bind")
        continue
      }
      #expect(binding.protocolID == subject.protocolID, "\(subject.identifier)")
      #expect(binding.variant == subject.variant, "\(subject.identifier)")
      #expect(record.quirks == subject.quirks, "\(subject.identifier)")
    }
    let gip = try #require(Self.registry.record(for: Self.gipUSB.identifier))
    #expect(gip.gipKeepAlivePolicy == .enabled)
    #expect(gip.gipStartupPackets == GIPStartupPacket.defaultSequence)
    let disabled = try #require(Self.registry.record(for: Self.gipKeepAliveDisabled.identifier))
    #expect(disabled.gipKeepAlivePolicy == .disabled)
    #expect(disabled.gipStartupPackets == GIPStartupPacket.defaultSequence)
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
  /// Bluetooth feature CRC. DualShock 4 Bluetooth groups the gyro endpoints.
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
