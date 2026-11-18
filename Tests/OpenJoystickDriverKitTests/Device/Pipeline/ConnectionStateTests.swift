import Testing

@testable import OpenJoystickDriverKit

/// The controller-side transport comes from the binding variant or observed evidence, never from
/// a USB host link alone.
struct ConnectionStateTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let name: String
    let protocolID: PhysicalProtocolID
    let variant: PhysicalProtocolVariantID?
    let backend: DeviceAccessBackend
    let hostTransport: PhysicalTransport?
    let expected: PhysicalTransport?

    var testDescription: String { name }
  }

  static let cases = [
    Case(
      name: "USB-HID DualShock 4",
      protocolID: .sonyDualShock4,
      variant: .usb,
      backend: .hid,
      hostTransport: .usb,
      expected: .usb
    ),
    Case(
      name: "Bluetooth DualShock 4",
      protocolID: .sonyDualShock4,
      variant: .bluetoothClassic,
      backend: .hid,
      hostTransport: .bluetoothClassic,
      expected: .bluetoothClassic
    ),
    Case(
      name: "raw-USB GIP",
      protocolID: .xboxGIP,
      variant: .usb,
      backend: .rawUSB,
      hostTransport: .usb,
      expected: .usb
    ),
    Case(
      name: "Steam dongle",
      protocolID: .valveSteamController,
      variant: .dongle,
      backend: .hid,
      hostTransport: .usb,
      expected: .proprietaryRadioReceiver
    ),
    Case(
      name: "HID pad without link evidence",
      protocolID: .hidDescriptor,
      variant: nil,
      backend: .hid,
      hostTransport: .usb,
      expected: nil
    ),
  ]

  @Test(arguments: cases)
  func transportComesFromVariantOrLinkEvidence(_ testCase: Case) async {
    let pipeline = DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1, productID: 2),
      transport: .hid(address: .ioKit(locationID: 1, interfaceNumber: nil)),
      driver: HIDDescriptorDriver(model: ControllerModelID(vendorID: 1, productID: 2)),
      dispatcher: CapturingOutputDispatcher()
    )
    let binding = ProtocolBinding(
      protocolID: testCase.protocolID,
      variant: testCase.variant,
      accessBackend: testCase.backend,
      interfaceNumber: nil,
      rule: .catalogRecord,
      matchedPredicates: [],
      record: nil
    )
    let interface = PhysicalInterfaceSignature(hostTransport: testCase.hostTransport)

    let state = await pipeline.connectionState(binding: binding, interface: interface)

    #expect(state.transport == testCase.expected)
    #expect(state.backend == testCase.backend)
    #expect(state.isConnected)
    #expect(state.power == .unknown)
  }
}
