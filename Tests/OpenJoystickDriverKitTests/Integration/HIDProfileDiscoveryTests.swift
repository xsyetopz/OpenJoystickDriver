import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct HIDProfileDiscoveryTests {
  @Test func hidAndRawUSBCatalogPartitionsAreDisjoint() {
    let registry = ParserRegistry()
    let hid = Set(registry.hidProfileIdentifiers().map { "\($0.vendorID):\($0.productID)" })
    let rawUSB = Set(registry.rawUSBProfileIdentifiers().map { "\($0.vendorID):\($0.productID)" })

    #expect(!hid.isEmpty)
    #expect(!rawUSB.isEmpty)
    #expect(hid.isDisjoint(with: rawUSB))
  }

  @Test func unknownIdentityUsesGenericHIDParser() {
    let parser = ParserRegistry().parser(for: DeviceIdentifier(vendorID: 65_534, productID: 1))
    #expect(parser is GenericHIDParser)
  }
}
