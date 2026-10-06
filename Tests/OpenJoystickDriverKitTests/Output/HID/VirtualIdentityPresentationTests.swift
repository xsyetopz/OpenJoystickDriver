import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualIdentityPresentationTests {
  @Test
  func microsoftIdentitiesUseXboxSymbols() {
    #expect(VirtualDeviceProfile.xboxOneS.presentation == .xbox)
    #expect(VirtualDeviceProfile.xboxOneS.presentation.controllerSymbolName == "xbox.logo")
  }

  /// The persona declares its glyphs; a Microsoft vendor ID alone does not select Xbox symbols.
  @Test
  func personaGlyphFamilyDecidesSymbolsNotVendorID() {
    let persona = VirtualDeviceProfile(
      vendorID: 0x045E,
      productID: 0x02FD,
      versionNumber: 0,
      productName: "Custom Pad",
      manufacturer: "Custom",
      transport: "USB",
      glyphFamily: .generic
    )
    #expect(persona.presentation == .generic)
  }

  @Test
  func genericHIDUsesGenericSymbol() {
    #expect(VirtualDeviceProfile.openJoystickDriverGenericHID.presentation == .generic)
  }

  @Test
  func publishedUSBIdentityLabelsNameTheOfficialProduct() {
    let xboxOneS = VirtualDeviceProfile.xboxOneS
    #expect(xboxOneS.productName == "Xbox Wireless Controller")
    #expect(xboxOneS.publishedUSBIdentityLabel == "Xbox Wireless Controller (045E:02FD)")
    #expect(xboxOneS.presentation.glyphFamily == .xbox)
    #expect(xboxOneS.presentation.controllerSymbolName == "xbox.logo")
  }
}
