import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record's `route` field, which marks the controllers the USB extension serves.
struct ControllerRecordRouteTests {
  @Test
  func decodesExtensionOwnedOnRawUSBFamily() throws {
    let document = try decode(
      #""modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}], "#
        + #""route": "ExtensionOwned""#
    )
    #expect(document.route == .extensionOwned)
    #expect(
      try decode(#""modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}]"#).route == nil
    )
  }

  @Test(arguments: ["extensionOwned", "System", ""])
  func rejectsUnknownRoutes(name: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": {\"family\": \"XboxGIP\"}}], "
          + "\"route\": \"\(name)\""
      )
    }
  }

  /// The extension claims raw USB interfaces, so a HID family cannot route through it.
  @Test(arguments: [#"{"family": "SonyDualSense"}"#, #"{"family": "VendorPS3ThirdParty"}"#])
  func rejectsExtensionOwnedOnHIDFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo)}], "
          + "\"route\": \"ExtensionOwned\""
      )
    }
  }

  @Test
  func bundledRecordsRouteExactlyGrantedXboxControllersThroughExtension() {
    let routed = ControllerRecordSet.bundled.records.values.filter { $0.route == .extensionOwned }
      .map(\.model).sorted()
    #expect(
      routed
        == [0x02D1, 0x02DD, 0x02E3, 0x02EA, 0x0B00, 0x0B0A, 0x0B12].map {
          ControllerModelID(vendorID: 0x045E, productID: $0)
        }
    )
  }

  /// Decodes a record for 045E:0B12 whose remaining top-level fields are `fields`.
  private func decode(_ fields: String) throws -> ControllerRecordDocument {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 1118, "productID": 2834, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}
