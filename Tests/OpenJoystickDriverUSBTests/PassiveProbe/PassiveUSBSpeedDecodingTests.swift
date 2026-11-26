import Testing

@testable import OpenJoystickDriverUSB

struct PassiveUSBSpeedDecodingTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let key: String
    let value: PassiveUSBRegistryNode.Value
    let speed: PassiveUSBNegotiatedSpeed?

    var testDescription: String { "\(key)=\(PassiveUSBRegistryFactParser.rawValue(value))" }
  }

  static let cases: [Case] = [
    Case(key: "USBSpeed", value: .unsignedInteger(0), speed: nil),
    Case(key: "USBSpeed", value: .unsignedInteger(1), speed: .full),
    Case(key: "USBSpeed", value: .unsignedInteger(2), speed: .low),
    Case(key: "USBSpeed", value: .unsignedInteger(3), speed: .high),
    Case(key: "USBSpeed", value: .unsignedInteger(4), speed: .superSpeed),
    Case(key: "USBSpeed", value: .unsignedInteger(5), speed: .superSpeedPlus),
    Case(key: "USBSpeed", value: .unsignedInteger(6), speed: .superSpeedPlus),
    Case(key: "USBSpeed", value: .unsignedInteger(7), speed: nil),
    Case(key: "Device Speed", value: .unsignedInteger(0), speed: .low),
    Case(key: "Device Speed", value: .unsignedInteger(1), speed: .full),
    Case(key: "Device Speed", value: .unsignedInteger(2), speed: .high),
    Case(key: "Device Speed", value: .unsignedInteger(3), speed: .superSpeed),
    Case(key: "Device Speed", value: .unsignedInteger(4), speed: .superSpeedPlus),
    Case(key: "Device Speed", value: .unsignedInteger(5), speed: .superSpeedPlus),
    Case(key: "Device Speed", value: .unsignedInteger(6), speed: nil),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(1_500_000), speed: .low),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(12_000_000), speed: .full),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(480_000_000), speed: .high),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(5_000_000_000), speed: .superSpeed),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(10_000_000_000), speed: .superSpeedPlus),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(20_000_000_000), speed: .superSpeedPlus),
    Case(key: "UsbLinkSpeed", value: .unsignedInteger(3), speed: nil),
    Case(key: "USB Speed", value: .unsignedInteger(3), speed: nil),
    Case(key: "USB Speed", value: .string("Super-Speed-Plus"), speed: .superSpeedPlus),
    Case(key: "USBSpeed", value: .string("SS"), speed: .superSpeed),
    Case(key: "Device Speed", value: .string("lowspeed"), speed: .low),
    Case(key: "UsbLinkSpeed", value: .string("Full-Speed"), speed: .full),
    Case(key: "USBSpeed", value: .string("highspeed"), speed: .high),
    Case(key: "USBSpeed", value: .string("ssplus"), speed: .superSpeedPlus),
    Case(key: "USBSpeed", value: .string("warp"), speed: nil),
    Case(key: "USBSpeed", value: .bytes([3]), speed: nil),
  ]

  @Test(arguments: cases)
  func speedPropertyDecodesToItsNegotiatedSpeed(_ testCase: Case) {
    let node = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: [testCase.key: testCase.value],
      children: []
    )

    let observation = PassiveUSBRegistryFactParser.observeSpeed(node)

    #expect(observation.speed == testCase.speed)
    #expect(observation.state == (testCase.speed == nil ? .absent : .observed))
    #expect(observation.properties.map(\.decodedSpeed) == [testCase.speed])
  }

  @Test
  func disagreeingSpeedPropertiesAreAmbiguousAndReportNoSpeed() {
    let node = PassiveUSBRegistryNode(
      serviceClass: "IOUSBHostDevice",
      properties: ["USBSpeed": .unsignedInteger(3), "Device Speed": .unsignedInteger(1)],
      children: []
    )

    let observation = PassiveUSBRegistryFactParser.observeSpeed(node)

    #expect(observation.state == .ambiguous)
    #expect(observation.speed == nil)
    #expect(observation.sources == ["USBSpeed", "Device Speed"])
  }
}
