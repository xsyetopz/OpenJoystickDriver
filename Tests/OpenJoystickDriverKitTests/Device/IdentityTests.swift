import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DeviceIdentifierTests {
  @Test func modelMatchesIgnoresSerialAndRejectsDifferentIdentities() {
    let first = DeviceIdentifier(vendorID: 1, productID: 2, serialNumber: "ABC123")
    let second = DeviceIdentifier(vendorID: 1, productID: 2, serialNumber: "XYZ789")
    let other = DeviceIdentifier(vendorID: 3, productID: 4)

    #expect(first.modelMatches(second))
    #expect(!first.modelMatches(other))
    #expect(!first.exactlyMatches(second))
  }

  @Test func exactRuntimeIdentifiersAreOpaqueStableAndDistinct() throws {
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

  @Test func locationRuntimeIdentifiersAreOpaqueAndDistinct() throws {
    let first = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, locationID: 7)
    let second = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, locationID: 8)

    #expect(first.runtimeIdentifier != second.runtimeIdentifier)
    try assertExactTokenShape(first.runtimeIdentifier)
    try assertExactTokenShape(second.runtimeIdentifier)
  }

  @Test func serialDisambiguatesDevicesThatReuseTheSameLocation() throws {
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

  @Test func modelRuntimeIdentifierIsExplicitlyDegraded() {
    let model = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E)
    let exact = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, serialNumber: "private")

    #expect(model.runtimeIdentifier == "M-045E-028E")
    #expect(model.runtimeIdentifier != exact.runtimeIdentifier)
  }

  @Test func applicationServiceEncodingsUseOpaqueSharedIdentifier() throws {
    let serial = "RPC-Private-Serial"
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x028E, serialNumber: serial)
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: identifier.vendorID,
      productID: identifier.productID,
      parser: "Test",
      connection: "USB",
      serialNumber: nil,
      runtimeIdentifier: identifier.runtimeIdentifier
    )
    let route = ApplicationServiceRemappingRoutePayload(
      vendorID: identifier.vendorID,
      productID: identifier.productID,
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
      let token = try #require(
        (object["runtime_identifier"] ?? object["runtimeIdentifier"]) as? String
      )
      #expect(token == identifier.runtimeIdentifier)
      try assertOpaqueExactToken(token, privateIdentity: serial)
    }
  }

  @Test func applicationServiceDeviceDescriptionRoundTripsDiscoverySource() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      parser: "Xbox360",
      connection: "USB",
      discoverySource: .hid,
      serialNumber: nil
    )

    let decoded = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONEncoder().encode(description)
    )

    #expect(decoded.discoverySource == .hid)
  }

  @Test func applicationServiceDeviceDescriptionRequiresDiscoverySource() throws {
    let description = ApplicationServiceDeviceDescription(
      name: "Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      parser: "Xbox360",
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil
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
