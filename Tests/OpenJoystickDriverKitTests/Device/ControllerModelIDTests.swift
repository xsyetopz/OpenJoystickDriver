import Testing

@testable import OpenJoystickDriverKit

struct ControllerModelIDTests {
  @Test
  func twoUnitsOfOneModelShareOneModelIDAndRecord() throws {
    let firstUnit = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "unit-a",
      locationID: 1,
      interfaceNumber: 0
    )
    let secondUnit = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x09CC,
      serialNumber: "unit-b",
      locationID: 2,
      interfaceNumber: 3
    )
    let otherModel = LogicalControllerID(
      vendorID: 0x054C,
      productID: 0x05C4,
      serialNumber: "unit-a"
    )

    #expect(firstUnit != secondUnit)
    #expect(firstUnit.hardware != secondUnit.hardware)
    #expect(firstUnit.model == secondUnit.model)
    #expect(firstUnit.model == ControllerModelID(vendorID: 0x054C, productID: 0x09CC))
    #expect(Set([firstUnit.model, secondUnit.model]).count == 1)
    #expect(firstUnit.model != otherModel.model)

    let registry = ProtocolDriverRegistry()
    let record = try #require(registry.record(for: firstUnit.model))
    #expect(registry.record(for: secondUnit.model) == record)
    #expect(ControllerRecordSet.bundled.records[secondUnit.model]?.model == firstUnit.model)
  }

  @Test
  func describesModelAsHexVendorAndProduct() {
    #expect(ControllerModelID(vendorID: 0x045E, productID: 0x02EA).description == "045E:02EA")
  }

  @Test
  func ordersByVendorThenProduct() {
    let models = [
      ControllerModelID(vendorID: 2, productID: 1),
      ControllerModelID(vendorID: 1, productID: 9),
      ControllerModelID(vendorID: 1, productID: 2),
    ]
    #expect(
      models.sorted() == [
        ControllerModelID(vendorID: 1, productID: 2),
        ControllerModelID(vendorID: 1, productID: 9),
        ControllerModelID(vendorID: 2, productID: 1),
      ]
    )
  }

  @Test
  func reportedModelRequiresBothIdentifiers() {
    #expect(ControllerModelID(vendorID: nil, productID: 0x1234) == nil)
    #expect(ControllerModelID(vendorID: 0x1234, productID: nil) == nil)
    #expect(ControllerModelID(vendorID: nil, productID: nil) == nil)
  }

  @Test
  func reportedModelRejectsIdentifiersThatWouldBeTruncated() {
    #expect(ControllerModelID(vendorID: UInt64(0x1_0000), productID: 0x1234) == nil)
    #expect(ControllerModelID(vendorID: 0x1234, productID: UInt64(0x1_0000)) == nil)
  }

  @Test
  func reportedModelPreservesRepresentableBoundaryValues() throws {
    let model = try #require(ControllerModelID(vendorID: UInt64(0xFFFF), productID: 0xFFFF))

    #expect(model.vendorID == .max)
    #expect(model.productID == .max)
  }
}
