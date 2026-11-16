import Testing

@testable import OpenJoystickDriverKit

struct ClaimedInterfaceContractTests {
  private let profile = DeviceTransportProfile(
    inputEndpoint: 0x82,
    outputEndpoint: 0x02,
    needsSetConfiguration: false
  )

  @Test
  func gipDataInterfaceWithProfileEndpointsPasses() {
    #expect(violation(.xboxGIP, .usb, [interface(0, 0xFF, 0x47, 0xD0)]) == nil)
  }

  @Test
  func unobservedInterfacesAreNotRejected() {
    #expect(violation(.xboxGIP, .usb, nil) == nil)
    #expect(violation(.xboxGIP, .usb, []) == nil)
  }

  @Test(arguments: [
    ("wrong class triple", interface(0, 0xFF, 0x5D, 0x01)),
    ("GIP triple off the data interface", interface(1, 0xFF, 0x47, 0xD0)),
    ("a third endpoint", interface(0, 0xFF, 0x47, 0xD0, extraEndpoint: true)),
    ("endpoints other than the profile's", interface(0, 0xFF, 0x47, 0xD0, input: 0x81)),
  ])
  func gipRejectsInterfacesOutsideItsContract(
    _ label: String,
    _ candidate: PhysicalInterfaceSignature
  ) {
    let claimed =
      candidate.interfaceNumber == 1
      ? DeviceTransportProfile(
        inputEndpoint: 0x82,
        outputEndpoint: 0x02,
        interfaceNumber: 1,
        needsSetConfiguration: false
      ) : profile
    #expect(
      ProtocolDriverRegistry.claimedInterfaceViolation(
        of: binding(.xboxGIP, .usb),
        profile: claimed,
        observed: PhysicalDevice(interfaces: [candidate])
      ) == .interfaceContractMismatch,
      "\(label)"
    )
  }

  @Test
  func driverKitObservationWithoutInterfaceFactsIsNotRejected() {
    let limited = PhysicalInterfaceSignature(accessBackend: .usbExtension, usbRoute: .usbExtension)
    #expect(violation(.xboxGIP, .usb, [limited]) == nil)
  }

  @Test
  func resolvedAlternateSettingIsOneChecked() {
    let bare = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      alternateSetting: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x47,
      interfaceProtocol: 0xD0,
      endpoints: []
    )
    let resolved = DeviceTransportProfile(
      inputEndpoint: 0x82,
      outputEndpoint: 0x02,
      alternateSetting: 1,
      needsSetConfiguration: false
    )
    #expect(
      ProtocolDriverRegistry.claimedInterfaceViolation(
        of: binding(.xboxGIP, .usb),
        profile: resolved,
        observed: PhysicalDevice(interfaces: [bare, interface(0, 0xFF, 0x47, 0xD0, alternate: 1)])
      ) == nil
    )
  }

  @Test
  func xusbVariantMustMatchInterfaceProtocol() {
    #expect(violation(.xboxXUSB, .wired, [interface(0, 0xFF, 0x5D, 0x01)]) == nil)
    #expect(
      violation(.xboxXUSB, .receiver, [interface(0, 0xFF, 0x5D, 0x01)])
        == .interfaceContractMismatch
    )
  }

  @Test
  func xidBindsByDeviceIdentityWithoutItsClassTriple() {
    // Linux xpad binds the Mad Catz Beat Pad by device ID rather than the XID class.
    #expect(violation(.xboxXID, .gamepad, [interface(0, 0xFF, 0x00, 0x00)]) == nil)
    #expect(violation(.xboxXID, .gamepad, [interface(0, 0x58, 0x42, 0x00)]) == nil)
  }

  @Test
  func gameSirVendorUSBRequiresVendorClassInterface() {
    #expect(violation(.vendorGameSir, .usb, [interface(0, 0xFF, 0x5D, 0x01)]) == nil)
    #expect(
      violation(.vendorGameSir, .usb, [interface(0, 0xFF, 0x00, 0x00, extraEndpoint: true)]) == nil
    )
    #expect(
      violation(.vendorGameSir, .usb, [interface(0, 0x03, 0x00, 0x00)])
        == .interfaceContractMismatch
    )
  }

  private func violation(
    _ protocolID: PhysicalProtocolID,
    _ variant: PhysicalProtocolVariantID,
    _ interfaces: [PhysicalInterfaceSignature]?
  ) -> ProtocolBindingReason? {
    ProtocolDriverRegistry.claimedInterfaceViolation(
      of: binding(protocolID, variant),
      profile: profile,
      observed: PhysicalDevice(interfaces: interfaces)
    )
  }

  private func binding(
    _ protocolID: PhysicalProtocolID,
    _ variant: PhysicalProtocolVariantID
  ) -> ProtocolBinding {
    ProtocolBinding(
      protocolID: protocolID,
      variant: variant,
      accessBackend: .rawUSB,
      interfaceNumber: nil,
      rule: .catalogRecord,
      matchedPredicates: [],
      record: nil
    )
  }
}

private func interface(
  _ number: UInt8,
  _ interfaceClass: UInt8,
  _ subclass: UInt8,
  _ interfaceProtocol: UInt8,
  alternate: UInt8 = 0,
  input: UInt8 = 0x82,
  extraEndpoint: Bool = false
) -> PhysicalInterfaceSignature {
  var endpoints = [
    PhysicalEndpointSignature(address: input, direction: .in, transferType: .interrupt),
    PhysicalEndpointSignature(address: 0x02, direction: .out, transferType: .interrupt),
  ]
  if extraEndpoint {
    endpoints.append(
      PhysicalEndpointSignature(address: 0x83, direction: .in, transferType: .interrupt)
    )
  }
  return PhysicalInterfaceSignature(
    interfaceNumber: number,
    alternateSetting: alternate,
    interfaceClass: interfaceClass,
    interfaceSubclass: subclass,
    interfaceProtocol: interfaceProtocol,
    endpoints: endpoints
  )
}
