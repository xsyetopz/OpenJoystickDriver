import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerSelectionTests {
  private func device(
    vendorID: UInt16,
    productID: UInt16,
    unitIdentifier: String? = nil
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test",
      vendorID: vendorID,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      unitIdentifier: unitIdentifier
    )
  }

  @Test
  func parsesAModelOnlyFromFourHexDigitsEach() {
    #expect(ControllerSelection("045e:0B12") == .model(vendorID: 0x045E, productID: 0x0B12))
    #expect(ControllerSelection("45e:0b12") == .id("45e:0b12"))
    #expect(ControllerSelection("045E:0B12:M") == .id("045E:0B12:M"))
    #expect(ControllerSelection("") == nil)
  }

  @Test
  func matchesByRuntimeOrUnitIDOrByModelInDeviceOrder() {
    let devices = [
      device(vendorID: 1, productID: 2, unitIdentifier: "unit-a"),
      device(vendorID: 1, productID: 3),
      device(vendorID: 1, productID: 2),
    ]
    func ids(_ selection: ControllerSelection) -> [String?] {
      selection.matches(in: devices).map(\.unitIdentifier)
    }
    func runtimeIDs(_ selection: ControllerSelection) -> [String] {
      selection.matches(in: devices).map(\.runtimeIdentifier)
    }

    #expect(ids(.model(vendorID: 1, productID: 2)) == ["unit-a", nil])
    #expect(ids(.id("unit-a")) == ["unit-a"])
    #expect(runtimeIDs(.id("0001:0003:M")) == ["0001:0003:M"])
    #expect(ids(.id("missing")).isEmpty)
  }
}
