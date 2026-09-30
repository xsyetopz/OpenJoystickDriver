import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DeviceIdentifierTests {
  @Test
  func logDescriptionNotesASerialWithoutRevealingIt() {
    let identifier = DeviceIdentifier(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "SERIAL-SECRET-123",
      locationID: 7
    )
    #expect(
      identifier.description == "DeviceIdentifier(VID:0x054C PID:0x09CC serial=present loc=7)"
    )
    #expect(!DeviceIdentifier(vendorID: 1, productID: 2).description.contains("serial"))
  }

  @Test
  func modelMatchesIgnoresSerialAndRejectsDifferentIdentities() {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, serialNumber: "ABC123")
    let second = DeviceIdentifier(vendorID: 1, productID: 2, serialNumber: "XYZ789")
    let other = DeviceIdentifier(vendorID: 3, productID: 4)

    #expect(first.modelMatches(second))
    #expect(!first.modelMatches(other))
    #expect(first.controllerIdentity != second.controllerIdentity)
  }

  @Test
  func controllerIdentityIgnoresLocationAndInterface() {
    let first = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: "pad",
      locationID: 1,
      interfaceNumber: 0
    )
    let second = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: "pad",
      locationID: 2,
      interfaceNumber: 2
    )

    #expect(first != second)
    #expect(first.controllerIdentity == second.controllerIdentity)
    #expect(
      first.controllerIdentity
        == ControllerIdentity(vendorID: 0x045E, productID: 0x0719, serialNumber: "pad")
    )
    #expect(first.controllerIdentity.identifiesPhysicalDevice)
    #expect(!ControllerIdentity(vendorID: 0x045E, productID: 0x0719).identifiesPhysicalDevice)
  }

  @Test
  func emptySerialIsNoSerial() {
    let empty = DeviceIdentifier(vendorID: 0x045E, productID: 0x0719, serialNumber: "")
    let none = DeviceIdentifier(vendorID: 0x045E, productID: 0x0719)

    #expect(empty.controllerIdentity.serialNumber == nil)
    #expect(!empty.controllerIdentity.identifiesPhysicalDevice)
    #expect(empty == none)
    #expect(empty.runtimeIdentifier == "M-045E-0719")
  }

  @Test
  func serialCannotMimicTheInterfaceComponentOfTheRuntimeToken() {
    let spoof = DeviceIdentifier(vendorID: 0x045E, productID: 0x0719, serialNumber: "pad:I:01")
    let slot = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      serialNumber: "pad",
      interfaceNumber: 1
    )

    #expect(spoof.runtimeIdentifier != slot.runtimeIdentifier)
  }

  @Test
  func keysDifferingOnlyByInterfaceAreDistinctLogicalControllers() throws {
    let slot0 = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      locationID: 7,
      interfaceNumber: 0
    )
    let slot1 = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0719,
      locationID: 7,
      interfaceNumber: 2
    )
    let unspecified = DeviceIdentifier(vendorID: 0x045E, productID: 0x0719, locationID: 7)

    #expect(Set([slot0, slot1, unspecified]).count == 3)
    #expect(slot0.runtimeIdentifier != slot1.runtimeIdentifier)
    #expect(slot0.runtimeIdentifier != unspecified.runtimeIdentifier)
    try assertExactTokenShape(slot1.runtimeIdentifier)
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
    let before = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x0B12,
      serialNumber: "Pad-Serial-42",
      locationID: 7
    )
    let after = DeviceIdentifier(
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
  func exactRuntimeIdentifiersAreOpaqueStableAndDistinct() throws {
    let serial = "Pad-Serial-42"
    let first = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, serialNumber: serial)
    let second = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x028E,
      serialNumber: "Pad-Serial-43"
    )
    let firstToken = first.runtimeIdentifier

    #expect(firstToken == first.runtimeIdentifier)
    #expect(firstToken != second.runtimeIdentifier)
    try assertOpaqueExactToken(firstToken, privateIdentity: serial)
    try assertOpaqueExactToken(second.runtimeIdentifier, privateIdentity: "Pad-Serial-43")
  }

  @Test
  func locationRuntimeIdentifiersAreOpaqueAndDistinct() throws {
    let first = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, locationID: 7)
    let second = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, locationID: 8)

    #expect(first.runtimeIdentifier != second.runtimeIdentifier)
    try assertExactTokenShape(first.runtimeIdentifier)
    try assertExactTokenShape(second.runtimeIdentifier)
  }

  @Test
  func serialDisambiguatesDevicesThatReuseTheSameLocation() throws {
    let first = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x028E,
      serialNumber: "first",
      locationID: 7
    )
    let second = DeviceIdentifier(
      vendorID: 0x045E,
      productID: 0x028E,
      serialNumber: "second",
      locationID: 7
    )

    #expect(first.runtimeIdentifier != second.runtimeIdentifier)
    try assertOpaqueExactToken(first.runtimeIdentifier, privateIdentity: "first")
    try assertOpaqueExactToken(second.runtimeIdentifier, privateIdentity: "second")
  }

  @Test
  func modelRuntimeIdentifierIsExplicitlyDegraded() {
    let model = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)
    let exact = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, serialNumber: "private")

    #expect(model.runtimeIdentifier == "M-045E-028E")
    #expect(model.runtimeIdentifier != exact.runtimeIdentifier)
  }

  @Test
  func applicationServiceEncodingsUseOpaqueSharedIdentifier() throws {
    let serial = "RPC-Private-Serial"
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, serialNumber: serial)
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
    let route = ApplicationServiceRemappingRoutePayload(
      vendorID: identifier.controllerIdentity.vendorID,
      productID: identifier.controllerIdentity.productID,
      runtimeIdentifier: identifier.runtimeIdentifier,
      selection: .remapping,
      eligibility: .eligible,
      activeProfileID: nil,
      activeProfileName: nil,
      applicationScope: nil,
      frontmostBundleIdentifier: nil,
      postEventAccess: .granted,
      failure: nil
    )

    for value in [description, route] as [any Encodable] {
      let encoded = try JSONEncoder().encode(AnyEncodable(value))
      let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
      #expect(object["runtime_identifier"] == nil)
      let token = try #require(object["runtimeIdentifier"] as? String)
      #expect(token == identifier.runtimeIdentifier)
      try assertOpaqueExactToken(token, privateIdentity: serial)
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
      bindingResult: .hidDescriptorFixture
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
      bindingResult: .hidDescriptorFixture
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

  private func assertOpaqueExactToken(_ token: String, privateIdentity: String) throws {
    try assertExactTokenShape(token)
    #expect(!token.contains(privateIdentity))
    #expect(!token.contains(Data(privateIdentity.utf8).base64EncodedString()))
    let hexIdentity = privateIdentity.utf8.map { String(format: "%02x", $0) }.joined()
    #expect(!token.lowercased().contains(hexIdentity))
  }

  private func assertExactTokenShape(_ token: String) throws {
    #expect(token.hasPrefix("E-"))
    var payload = String(token.dropFirst(2)).replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    let decoded = try #require(Data(base64Encoded: payload))
    #expect(decoded.count == 32)
  }
}

private struct AnyEncodable: Encodable {
  private let encodeValue: (Encoder) throws -> Void

  init(_ value: any Encodable) { self.encodeValue = value.encode }

  func encode(to encoder: Encoder) throws { try encodeValue(encoder) }
}
