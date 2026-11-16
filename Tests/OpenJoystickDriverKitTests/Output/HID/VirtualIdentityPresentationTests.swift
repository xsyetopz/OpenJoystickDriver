import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualIdentityPresentationTests {
  @Test
  func microsoftIdentitiesUseXboxSymbols() {
    #expect(VirtualDeviceProfile.sdlCompatible.presentation == .xbox)
    #expect(VirtualDeviceProfile.sdlCompatible.presentation.controllerSymbolName == "xbox.logo")
  }

  /// The persona declares its glyphs; a Microsoft vendor ID alone does not select Xbox symbols.
  @Test
  func personaGlyphFamilyDecidesSymbolsNotVendorID() {
    let persona = VirtualDeviceProfile(
      vendorID: 0x045E,
      productID: 0x0B0C,
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
    #expect(VirtualDeviceProfile.generic.presentation == .generic)
  }

  @Test
  func publishedUSBIdentityLabelsNameOfficialProduct() {
    let adaptive = VirtualDeviceProfile.sdlCompatible
    #expect(adaptive.productName == "Xbox Adaptive Controller")
    #expect(adaptive.publishedUSBIdentityLabel == "Xbox Adaptive Controller (045E:0B0C)")
    #expect(adaptive.presentation.glyphFamily == .xbox)
    #expect(adaptive.presentation.controllerSymbolName == "xbox.logo")
  }

  @Test
  func physicalFamiliesMapToTheirOwnGlyphs() {
    #expect(PhysicalProtocolID.sonySixaxis.physicalPresentation == .playstation)
    #expect(PhysicalProtocolID.sonyDualSense.physicalPresentation == .playstation)
    #expect(PhysicalProtocolID.xboxGIP.physicalPresentation == .xbox)
    #expect(PhysicalProtocolID.hidDescriptor.physicalPresentation == .generic)
  }
}
