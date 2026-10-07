import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct InputCapabilitiesTests {
  @Test(arguments: [UInt16(0x05C4), UInt16(0x09CC), UInt16(0x0CE6), UInt16(0x0DF2)])
  func sonyParserCapabilitiesReachTheExactDevicePayload(_ productID: UInt16) async throws {
    let manager = DeviceManager(dispatcher: LoggingOutputDispatcher())
    await manager.handleHIDEvent(
      .connected(
        connection: HIDDeviceConnection(
          physicalDevice: PhysicalDevice(
            vendorID: 0x054C,
            productID: productID,
            productName: "Test",
            transportProperty: "USB",
            physicalLocationIdentifier: 77,
            interfaces: [hostHIDInterface(.usb)]
          ),
          routingLocationID: 77,
        ),
        ownership: .exclusive
      )
    )
    let descriptions = await manager.connectedDeviceDescriptions()
    let description = try #require(descriptions.first)
    #expect(description.vendorID == 0x054C && description.productID == productID)
    #expect(description.capabilities.motion)
    #expect(description.capabilities.touchContactCount == 2)
    #expect(description.capabilities.touchSurfaces == [.primary])
    let dualSense: Set<ControlID> = [
      .guide, .leftTriggerButton, .rightTriggerButton, .touchpadClick, .microphone,
    ]
    let extra: Set<ControlID>
    switch productID {
    case 0x0DF2: extra = dualSense.union([.paddleLeft1, .paddleRight1, .auxiliary1, .auxiliary2])
    case 0x0CE6: extra = dualSense
    default: extra = [.guide, .touchpadClick, .leftTriggerButton, .rightTriggerButton]
    }
    #expect(description.capabilities.controls == ControlID.xboxLayout.union(extra))
    let encoded = try JSONEncoder().encode(
      ApplicationServiceDeviceDescription(snapshot: description)
    )
    let decoded = try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: encoded)
    #expect(decoded.capabilities == description.capabilities)
    #expect(decoded.runtimeIdentifier == description.runtimeIdentifier)
    await manager.stop()
  }

  @Test
  func devicePayloadRequiresInputHealthAndCapabilities() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture
    )
    let data = try JSONEncoder().encode(description)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    for key in ["inputHealth", "capabilities"] {
      var incomplete = object
      incomplete.removeValue(forKey: key)
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
          ApplicationServiceDeviceDescription.self,
          from: JSONSerialization.data(withJSONObject: incomplete)
        )
      }
    }
  }

  @Test
  func devicePayloadRoundTripsConnectionState() throws {
    let state = ControllerConnectionState(
      transport: .bluetoothClassic,
      backend: .ioHID,
      isConnected: true,
      power: ControllerConnectionState.Power(
        charging: .charging,
        battery: BatteryLevel(percentage: 90...99),
        wiredPower: true
      )
    )
    let description = ApplicationServiceDeviceDescription(
      name: "DualShock 4",
      vendorID: 0x054C,
      productID: 0x09CC,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      connectionState: state
    )

    let encoded = try JSONEncoder().encode(description)
    let decoded = try JSONDecoder().decode(ApplicationServiceDeviceDescription.self, from: encoded)

    #expect(decoded.connectionState == state)
    #expect(decoded.connectionState?.power.battery.percentageText == "90-99%")
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let encodedState = try #require(object["connectionState"] as? [String: Any])
    #expect(encodedState["transport"] as? String == "bluetoothClassic")
    #expect(encodedState["backend"] as? String == "ioHID")
    let encodedPower = try #require(encodedState["power"] as? [String: Any])
    let encodedBattery = try #require(encodedPower["battery"] as? [String: Any])
    #expect(encodedBattery["percentage"] as? [Int] == [90, 99])
  }

  @Test
  func batteryLevelKeepsTheDevicePrecision() throws {
    let exact = BatteryLevel(percentage: 73...73)
    #expect(exact.percentageText == "73%")
    #expect(try JSONEncoder().encode(exact) == Data(#"{"percentage":[73,73]}"#.utf8))
    #expect(BatteryLevel.unknown.percentageText == nil)
    #expect(try JSONEncoder().encode(BatteryLevel.unknown) == Data("{}".utf8))
    for invalid in [#"{"percentage":[9,0]}"#, #"{"percentage":[95,101]}"#] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(BatteryLevel.self, from: Data(invalid.utf8))
      }
    }
  }

  @Test
  func unsupportedParserDoesNotAdvertiseRawSamples() {
    let parser = HIDDescriptorDriver(identifier: DeviceIdentifier(vendorID: 1, productID: 2))
    #expect(!parser.capabilities.motion)
    #expect(parser.capabilities.touchContactCount == 0)
  }
}
