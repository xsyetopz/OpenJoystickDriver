import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct LogicalControllerIDTests {
  @Test
  func logDescriptionNotesASerialWithoutRevealingIt() {
    let identifier = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "SERIAL-SECRET-123",
      locationID: 7
    )
    #expect(
      identifier.description == "LogicalControllerID(VID:0x054C PID:0x09CC serial=present loc=7)"
    )
    #expect(!LogicalControllerID(vendorID: 1, productID: 2).description.contains("serial"))
  }

  @Test
  func hardwareIdentityIgnoresTheAddress() {
    let first = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: "pad",
      locationID: 1,
      interfaceNumber: 0
    )
    let second = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: "pad",
      locationID: 2,
      interfaceNumber: 2
    )

    #expect(first != second)
    #expect(first.hardware == second.hardware)
    #expect(
      first.hardware
        == ControllerHardwareIdentity(
          model: ControllerModelID(vendorID: 0x045E, productID: 0x0719),
          serialNumber: "pad"
        )
    )
    #expect(first.hardware.identifiesPhysicalDevice)
    #expect(!ControllerHardwareIdentity(model: first.model).identifiesPhysicalDevice)
  }

  @Test
  func oneControllerOnUSBAndBluetoothHasOneHardwareIdentityAndTwoAddresses() async throws {
    let usb = DeviceManager.usbIdentifier(
      for: USBTransportDevice(
        route: .rawUSB,
        serviceID: 11,
        vendorID: 0x054C,
        productID: 0x09CC,
        locationID: 0x0013_0000,
        serialNumber: "pad"
      ),
      claiming: DeviceTransportProfile(
        inputEndpoint: 0x84,
        outputEndpoint: 0x03,
        interfaceNumber: 3,
        needsSetConfiguration: false
      )
    )
    let bluetoothConnection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x09CC,
        productName: "Wireless Controller",
        serialNumber: "pad",
        transportProperty: "Bluetooth",
        physicalLocationIdentifier: 0x5A00_0000,
        interfaces: [hostHIDInterface(.bluetoothClassic)]
      ),
      routingAddress: .ioKit(locationID: 0x5A00_0000, interfaceNumber: nil)
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let bluetooth = try #require(
      await manager.hidIdentifier(for: bluetoothConnection, role: .location)
    )

    #expect(usb.hardware == bluetooth.hardware)
    #expect(
      usb.hardware
        == ControllerHardwareIdentity(
          model: ControllerModelID(vendorID: 0x054C, productID: 0x09CC),
          serialNumber: "pad"
        )
    )
    #expect(usb.address == .ioKit(locationID: 0x0013_0000, interfaceNumber: 3))
    #expect(bluetooth.address == .ioKit(locationID: 0x5A00_0000, interfaceNumber: nil))
    #expect(usb != bluetooth)
  }

  @Test
  func emptySerialIsNoSerial() {
    let empty = LogicalControllerID(vendorID: 0x045E, productID: 0x0719, serialNumber: "")
    let none = LogicalControllerID(vendorID: 0x045E, productID: 0x0719)

    #expect(empty.hardware.serialNumber == nil)
    #expect(!empty.hardware.identifiesPhysicalDevice)
    #expect(empty == none)
  }

  @Test
  func keysDifferingOnlyByInterfaceAreDistinctLogicalControllers() {
    let slot0 = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0719,
      locationID: 7,
      interfaceNumber: 0
    )
    let slot1 = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0719,
      locationID: 7,
      interfaceNumber: 2
    )
    let unspecified = LogicalControllerID(vendorID: 0x045E, productID: 0x0719, locationID: 7)

    #expect(Set([slot0, slot1, unspecified]).count == 3)
    #expect(slot0.testPortKey != slot1.testPortKey)
    #expect(slot0.testPortKey != unspecified.testPortKey)
    #expect(
      UserSpaceVirtualDeviceConstants.serialNumber(for: slot0)
        != UserSpaceVirtualDeviceConstants.serialNumber(for: slot1)
    )
    #expect(
      UserSpaceVirtualDeviceConstants.serialNumber(for: slot0)
        != UserSpaceVirtualDeviceConstants.serialNumber(for: unspecified)
    )
    #expect(slot0.description.hasSuffix(" if=0)"))
    #expect(!unspecified.description.contains("if="))
  }

  @Test
  func virtualIdentityOfASerialControllerSurvivesAPortChange() {
    let before = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "Pad-Serial-42",
      locationID: 7
    )
    let after = LogicalControllerID(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "Pad-Serial-42",
      locationID: 9
    )
    #expect(
      UserSpaceVirtualDeviceConstants.serialNumber(for: before)
        == UserSpaceVirtualDeviceConstants.serialNumber(for: after)
    )
    #expect(
      UserSpaceVirtualDeviceConstants.locationID(for: before)
        == UserSpaceVirtualDeviceConstants.locationID(for: after)
    )
  }

  @Test
  func applicationServiceEncodingsCarryTheSessionTokenAndNotTheSerial() throws {
    let serial = "RPC-Private-Serial"
    let identifier = LogicalControllerID(vendorID: 0x045E, productID: 0x028E, serialNumber: serial)
    let token = ControllerSessionToken.issue()
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: token
    )
    let route = ApplicationServiceRemappingRoutePayload(
      vendorID: identifier.model.vendorID,
      productID: identifier.model.productID,
      sessionToken: token,
      selection: .remapping,
      eligibility: .eligible,
      activeProfileID: nil,
      activeProfileName: nil,
      applicationScope: nil,
      frontmostAppID: nil,
      postEventAccess: .granted,
      failure: nil
    )

    for value in [description, route] as [any Encodable] {
      let encoded = try JSONEncoder().encode(AnyEncodable(value))
      let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(object["sessionToken"] as? String == token.rawValue)
      #expect(String(bytes: encoded, encoding: .utf8)?.contains(serial) == false)
    }
  }

  @Test
  func applicationServiceDeviceDescriptionRoundTripsDiscoverySource() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )

    #expect(decoded.discoverySource == .hid)
  }

  @Test
  func applicationServiceDeviceDescriptionRequiresDiscoverySource() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
    )
    let encoded = try JSONEncoder().encode(description)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "discoverySource")

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(
        ApplicationServiceDeviceDescription.self,
        from: JSONSerialization.data(withJSONObject: object)
      )
    }
  }
}

private struct AnyEncodable: Encodable {
  private let encodeValue: (Encoder) throws -> Void

  init(_ value: any Encodable) { self.encodeValue = value.encode }

  func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
