import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct InputCapabilitiesTests {
  @Test(arguments: [UInt16(0x05C4), UInt16(0x09CC), UInt16(0x0CE6), UInt16(0x0DF2)])
  func sonyParserCapabilitiesReachTheExactDevicePayload(_ productID: UInt16) async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    await manager.handleHIDEvent(
      .connected(
        vendorID: 0x054C,
        productID: productID,
        serialNumber: nil,
        locationID: 77,
        productName: "Test",
        transport: "USB",
        ownership: .exclusive
      )
    )
    let descriptions = await manager.connectedDeviceDescriptions()
    let description = try #require(descriptions.first)
    #expect(description.vendorID == 0x054C && description.productID == productID)
    #expect(description.physicalInputCapabilities.rawMotion)
    #expect(description.physicalInputCapabilities.touchContactsPerFrame == 2)
    #expect(description.physicalInputCapabilities.touchSurfaces == [.primary])
    let expected: [Button]
    switch productID {
    case 0x0DF2:
      expected = [.touchpad, .mute, .leftFunction, .rightFunction, .leftPaddle, .rightPaddle]
    case 0x0CE6: expected = [.touchpad, .mute]
    default: expected = [.touchpad]
    }
    #expect(description.physicalInputCapabilities.additionalButtons == expected)
    let encoded = try JSONEncoder().encode(description)
    let decoded = try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: encoded)
    #expect(decoded.physicalInputCapabilities == description.physicalInputCapabilities)
    #expect(decoded.runtimeIdentifier == description.runtimeIdentifier)
    await manager.stop()
  }

  @Test func olderDevicePayloadDefaultsToNoSensorCapability() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      parser: "Generic HID",
      connection: "USB",
      serialNumber: nil
    )
    let data = try JSONEncoder().encode(description)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "physicalInputCapabilities")
    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
    #expect(decoded.physicalInputCapabilities == .none)
  }

  @Test func unsupportedParserDoesNotAdvertiseRawSamples() {
    let parser = ParserRegistry().parser(for: DeviceIdentifier(vendorID: 1, productID: 2))
    #expect(parser.physicalInputCapabilities == .none)
  }
}

extension InputCapabilitiesTests {
  @Test func olderSensorCapabilityPayloadDefaultsToNoAdditionalButtons() throws {
    let data = Data(#"{"rawMotion":true,"touchContactsPerFrame":2}"#.utf8)
    let decoded = try JSONDecoder().decode(PhysicalControllerInputCapabilities.self, from: data)
    #expect(decoded.rawMotion)
    #expect(decoded.touchContactsPerFrame == 2)
    #expect(decoded.additionalButtons.isEmpty)
    #expect(decoded.touchSurfaces.isEmpty)
  }

  @Test(arguments: [
    (UInt16(0x057E), UInt16(0x2006), [Button.leftSL, .leftSR]),
    (UInt16(0x057E), UInt16(0x2007), [Button.rightSL, .rightSR]),
    (UInt16(0x057E), UInt16(0x2009), [Button]()),
    (UInt16(0x28DE), UInt16(0x1102), [Button.leftGrip, .rightGrip, .leftPadClick, .rightPadClick])
  ]) func additionalButtonCapabilitiesFollowTheSelectedParser(
    vendorID: UInt16, productID: UInt16, expected: [Button]
  ) throws {
    let parser = ParserRegistry().parser(
      for: DeviceIdentifier(vendorID: vendorID, productID: productID)
    )
    #expect(parser.physicalInputCapabilities.additionalButtons == expected)
    let encoded = try JSONEncoder().encode(parser.physicalInputCapabilities)
    #expect(try JSONDecoder().decode(PhysicalControllerInputCapabilities.self, from: encoded)
      == parser.physicalInputCapabilities)
  }
}
