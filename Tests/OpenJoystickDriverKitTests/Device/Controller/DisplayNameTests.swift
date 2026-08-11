import Testing

@testable import OpenJoystickDriverKit

struct ControllerDisplayNameTests {
  @Test func usesObservedProductString() {
    #expect(
      controllerDisplayName(productName: "  Device Product  ", vendorID: 1, productID: 2)
        == "Device Product"
    )
  }

  @Test func usesNumericFallbackWhenProductStringIsUnavailable() {
    #expect(
      controllerDisplayName(productName: nil, vendorID: 0x045E, productID: 0x02EA)
        == "Controller 045e:02ea"
    )
    #expect(
      controllerDisplayName(productName: "   ", vendorID: 0x3537, productID: 0x1010)
        == "Controller 3537:1010"
    )
  }
}
