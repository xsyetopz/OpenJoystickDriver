import Testing

@testable import OpenJoystickDriverKit

struct RawUSBAdmissionPolicyTests {
  private let registry = ParserRegistry()

  @Test func unknownDeviceUsingGenericHIDFallbackIsRejected() {
    let identifier = DeviceIdentifier(vendorID: 0x0001, productID: 0x0001)

    #expect(registry.parser(for: identifier) is GenericHIDParser)
    #expect(!registry.supportsRawUSBPipeline(for: identifier))
  }

  @Test func catalogedGIPDeviceIsAdmitted() {
    let identifier = DeviceIdentifier(vendorID: 1_118, productID: 721)

    #expect(registry.parser(for: identifier) is GIPParser)
    #expect(registry.supportsRawUSBPipeline(for: identifier))
  }

  @Test func catalogedXbox360DeviceIsAdmitted() {
    let identifier = DeviceIdentifier(vendorID: 1_118, productID: 1_817)

    #expect(registry.parser(for: identifier) is Xbox360Parser)
    #expect(registry.supportsRawUSBPipeline(for: identifier))
  }

  @Test func catalogedXIDDeviceIsAdmitted() {
    let identifier = DeviceIdentifier(vendorID: 0x045E, productID: 0x0202)

    #expect(registry.parser(for: identifier) is XIDParser)
    #expect(registry.supportsRawUSBPipeline(for: identifier))
  }
}
