import Testing

@testable import OpenJoystickDriverKit

struct CompatibilityProtocolBackendTests {
  @Test func xbox360CloneSpoofsFirstPartyWiredPad() {
    let route = CompatibilityProtocolBackendCatalog.route(for: .xusb)
    #expect(route?.canPublish == true)
    #expect(route?.selectableIdentity == .sdl2_3)
    #expect(route?.firstParty.vendorID == 0x045E)
    #expect(route?.firstParty.productID == 0x028E)
    #expect(route?.containsExplicit(vendorID: 0x045E, productID: 0x028E) == true)
    #expect(route?.containsExplicit(vendorID: 0x413D, productID: 0x2104) == false)
  }

  @Test func gipCloneSpoofsFirstPartyXboxSeries() {
    let route = CompatibilityProtocolBackendCatalog.route(for: .gip)
    #expect(route?.canPublish == true)
    #expect(route?.selectableIdentity == .appleGameController)
    #expect(route?.firstParty.productID == 0x0B13)
    #expect(route?.containsExplicit(vendorID: 0x3537, productID: 0x1010) == false)
  }

  @Test func hidDialectIdentitiesAreAutomaticForMatchingPhysicalDevices() {
    #expect(CompatibilityProtocolBackendCatalog.route(for: .hid) == nil)
    #expect(CompatibilityProtocolBackendCatalog.canSelect(.dualShock4, for: .hid) == true)
    #expect(CompatibilityProtocolBackendCatalog.canSelect(.dualSense, for: .hid) == true)
    #expect(CompatibilityProtocolBackendCatalog.canSelect(.switchPro, for: .hid) == true)
    #expect(CompatibilityProtocolBackendCatalog.canSelect(.dualShock4, for: .gip) == false)
    #expect(
      CompatibilityProtocolBackendCatalog.hidDialectRoutes.map(\.selectableIdentity)
        == [.dualShock4, .dualSense, .switchPro]
    )
    let ds4 = ApplicationServiceDeviceDescription(
      name: "DualShock 4",
      vendorID: 0x054C,
      productID: 0x05C4,
      parser: "DS4",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .dualShock4
    )
    let generic = ApplicationServiceDeviceDescription(
      name: "Generic",
      vendorID: 0x0001,
      productID: 0x0001,
      parser: "GenericHID",
      connection: "USB",
      serialNumber: nil,
      protocolVariant: .genericHID
    )
    #expect(
      CompatibilityProtocolBackendCatalog.hidDialectRoute(for: ds4)?.selectableIdentity
        == .dualShock4
    )
    #expect(CompatibilityProtocolBackendCatalog.hidDialectRoute(for: generic) == nil)
  }

  @Test func catalogHasOneRoutePerWireFamily() {
    let families = Set(CompatibilityProtocolBackendCatalog.routes.map(\.subfamily))
    #expect(families == Set(PhysicalProtocolSubfamily.allCases))
    #expect(
      CompatibilityProtocolBackendCatalog.routes.count == PhysicalProtocolSubfamily.allCases.count
    )
  }
}
