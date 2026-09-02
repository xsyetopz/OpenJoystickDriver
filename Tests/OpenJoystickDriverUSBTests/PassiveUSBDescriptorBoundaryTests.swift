import Testing

@testable import OpenJoystickDriverUSB

struct PassiveUSBDescriptorBoundaryTests {
  @Test func duplicateEndpointInsideValidAlternateIsRejected() {
    let bytes: [UInt8] = [
      9, 2, 32, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 2, 0xFF, 0, 0, 0, 7, 5, 1, 3, 1, 0, 1, 7, 5, 1,
      3, 1, 0, 1
    ]
    #expect(throws: PassiveUSBDescriptorBlobError.impossibleEndpointOwnership) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(bytes)
    }
  }

  @Test func duplicateSSPCompanionIsRejected() {
    let bytes: [UInt8] = [
      9, 2, 47, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0, 0, 0, 7, 5, 1, 1, 0, 4, 1, 6, 0x30,
      0, 0x80, 1, 0, 8, 0x31, 0, 0, 0x51, 0xC3, 0, 0, 8, 0x31, 0, 0, 0x51, 0xC3, 0, 0
    ]
    let context = PassiveUSBSuperSpeedPlusValidationContext(
      maxIsoBytesPerBiGen1: 60_000,
      numberOfLanes: 1,
      laneSpeedMantissa: 1,
      laneSpeedMantissaGen1: 1
    )
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        bytes,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: context
      )
    }
  }

  @Test func SSPCompanionAfterNonIsochronousEndpointIsRejected() {
    let bytes: [UInt8] = [
      9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0, 0, 0, 7, 5, 1, 2, 0, 4, 0, 6, 0x30,
      0, 0, 0, 0, 8, 0x31, 0, 0, 0x51, 0xC3, 0, 0
    ]
    #expect(bytes.count == 39)
    #expect(throws: PassiveUSBDescriptorBlobError.orphanCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        bytes,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
  }

  @Test func trailingOneByteDescriptorFragmentIsRejected() {
    let bytes: [UInt8] = [9, 2, 19, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 0, 0xFF, 0, 0, 0, 1]
    #expect(throws: PassiveUSBDescriptorBlobError.truncated) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(bytes)
    }
  }

  @Test func descriptorOwnershipAndSSPMalformedBoundariesAreRejected() throws {
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([
        9, 2, 25, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 0, 0xFF, 0x47, 0xD0, 0, 1
      ])
    }
    #expect(throws: PassiveUSBDescriptorBlobError.totalLengthMismatch) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse([
        9, 2, 18, 0, 0, 1, 0, 0x80, 0x32, 9, 2, 18, 0, 0, 1, 0, 0x80, 0x32
      ])
    }
    let context = PassiveUSBSuperSpeedPlusValidationContext(
      maxIsoBytesPerBiGen1: 60_000,
      numberOfLanes: 1,
      laneSpeedMantissa: 1,
      laneSpeedMantissaGen1: 1
    )
    var zeroLane = [UInt8](repeating: 0, count: 0)
    zeroLane = [
      9, 2, 39, 0, 1, 1, 0, 0x80, 0x32, 9, 4, 0, 0, 1, 0xFF, 0x47, 0xD0, 0, 7, 5, 1, 1, 0, 2, 1, 6,
      0x30, 0, 0x80, 1, 0, 8, 0x31, 0, 0, 0x50, 0xC3, 0, 0
    ]
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        zeroLane,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 0,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 1
        )
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        zeroLane,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: 60_000,
          numberOfLanes: 1,
          laneSpeedMantissa: 1,
          laneSpeedMantissaGen1: 0
        )
      )
    }
    #expect(throws: PassiveUSBDescriptorBlobError.invalidCompanionDescriptor) {
      try _ = PassiveUSBConfigurationDescriptorParser.parse(
        zeroLane,
        negotiatedSpeed: .superSpeedPlus,
        superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext(
          maxIsoBytesPerBiGen1: UInt32.max,
          numberOfLanes: UInt32.max,
          laneSpeedMantissa: UInt32.max,
          laneSpeedMantissaGen1: 1
        )
      )
    }
    _ = context
  }
}
