import Testing

@testable import OpenJoystickDriverKit

struct USBDetectionAdmissionTests {
  @Test func rejectedDeviceDoesNotReadOptionalDescriptorStrings() {
    var didReadDescriptorStrings = false

    let admission = resolveRawUSBAdmission(
      parserRegistry: ParserRegistry(),
      vendorID: 65_535,
      productID: 65_535,
      locationID: 1
    ) {
      didReadDescriptorStrings = true
      return (serialNumber: "unexpected", productName: "unexpected")
    }

    #expect(admission == nil)
    #expect(!didReadDescriptorStrings)
  }

  @Test func admittedDeviceReadsDescriptorStringsAndBuildsItsRuntimeIdentity() throws {
    var descriptorReadCount = 0

    let admission = try #require(
      resolveRawUSBAdmission(
        parserRegistry: ParserRegistry(),
        vendorID: 1_118,
        productID: 721,
        locationID: 513
      ) {
        descriptorReadCount += 1
        return (serialNumber: "serial", productName: "Xbox Controller")
      }
    )

    #expect(descriptorReadCount == 1)
    #expect(admission.identifier.vendorID == 1_118)
    #expect(admission.identifier.productID == 721)
    #expect(admission.identifier.serialNumber == "serial")
    #expect(admission.identifier.locationID == 513)
    #expect(admission.productName == "Xbox Controller")
  }
}
