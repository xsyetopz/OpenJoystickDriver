import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

extension PassiveUSBDescriptorProbeTests {
  @Test
  func endpointCountsAddressesAttributesAndIntervalsAreStrict() throws {
    func blob(endpointCount: UInt8, endpoint: [UInt8]) -> [UInt8] {
      [
        9, 2, UInt8(18 + endpoint.count), 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, endpointCount, 0xFF,
        0x47, 0xD0, 0,
      ] + endpoint
    }
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 2, endpoint: [7, 5, 1, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidEndpointAddress) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 0, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidEndpointAddress) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 0x71, 3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 0xC3, 0, 0, 1])
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 3, 0, 0, 0]),
        negotiatedSpeed: .full
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(endpointCount: 1, endpoint: [7, 5, 1, 1, 0, 0, 17]),
        negotiatedSpeed: .high
      )
    }
  }

  @Test
  func intervalBoundariesAreSpeedAndTransferScoped() throws {
    func parse(
      _ transfer: UInt8,
      _ interval: UInt8,
      _ speed: PassiveUSBNegotiatedSpeed
    ) throws -> UInt64? {
      try PassiveUSBConfigurationDescriptorParser.parse(
        [
          9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, transfer,
          0, 0, interval,
        ],
        negotiatedSpeed: speed
      ).interfaces[0].endpoints[0].nominalIntervalMicroseconds
    }
    #expect(try parse(3, 1, .full) == 1_000)
    #expect(try parse(3, 255, .full) == 255_000)
    #expect(try parse(3, 1, .high) == 125)
    #expect(try parse(3, 16, .high) == 4_096_000)
    #expect(try parse(1, 1, .full) == 1_000)
    #expect(try parse(1, 16, .full) == 32_768_000)
    #expect(try parse(2, 1, .high) == nil)
    #expect(try parse(0, 1, .high) == nil)
  }

  @Test
  func endpointUsageAndLowSpeedTransferRulesAreIndependent() throws {
    func blob(attributes: UInt8, interval: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        64, 0, interval,
      ]
    }
    for usage in [UInt8(0x03), UInt8(0x13)] {
      var base = blob(attributes: usage, interval: usage == 0x13 ? 8 : 1)
      base[2] = 31
      let parsed = try PassiveUSBConfigurationDescriptorParser.parse(
        base + [6, 0x30, 0, 0, 64, 0],
        negotiatedSpeed: .superSpeedPlus
      )
      #expect(parsed.interfaces[0].endpoints.count == 1)
    }
    for usage in [UInt8(0x23), UInt8(0x33)] {
      #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
        try PassiveUSBConfigurationDescriptorParser.parse(
          blob(attributes: usage, interval: 1),
          negotiatedSpeed: .superSpeed
        )
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(blob(attributes: 0x13, interval: 8))
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(attributes: 2, interval: 1),
        negotiatedSpeed: .low
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try PassiveUSBConfigurationDescriptorParser.parse(
        blob(attributes: 1, interval: 1),
        negotiatedSpeed: .low
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try PassiveUSBConfigurationDescriptorParser.parse(blob(attributes: 1, interval: 17))
    }
  }

  @Test
  func isochronousUsageValuesAccept0To2AndReject3() throws {
    func blob(_ attributes: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        0, 2, 1,
      ]
    }
    for attributes in [UInt8(1), UInt8(0x11), UInt8(0x21)] {

      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(attributes))
      }
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidTransferAttributes) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(0x31))
    }
  }

  @Test
  func isochronousSynchronizationValuesAreAllAccepted() throws {
    func blob(_ attributes: UInt8) -> [UInt8] {
      [
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, attributes,
        0, 2, 1,
      ]
    }
    for attributes in [UInt8(1), UInt8(5), UInt8(9), UInt8(13)] {
      #expect(throws: Never.self) {
        try _ = PassiveUSBConfigurationDescriptorParser.parse(blob(attributes))
      }
    }
  }

  @Test
  func periodicZeroIsInvalidBeforeSpeedIsKnown() {
    let bytes: [UInt8] = [
      9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 3, 0, 0, 0,
    ]
    #expect(throws: PassiveUSBDescriptorBlobError.invalidInterval) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(bytes)
    }
  }
}
