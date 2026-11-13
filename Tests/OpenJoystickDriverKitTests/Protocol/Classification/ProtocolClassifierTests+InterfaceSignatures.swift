import Foundation
import Testing

@testable import OpenJoystickDriverKit

extension ProtocolClassifierTests {
  // MARK: - Interface signatures

  @Test(
    arguments: [
      (0x58, 0x42, 0x00, PhysicalProtocolID.xboxXID, PhysicalProtocolVariantID.gamepad),
      (0xFF, 0x5D, 0x01, .xboxXUSB, .wired), (0xFF, 0x5D, 0x81, .xboxXUSB, .receiver),
      (0xFF, 0x47, 0xD0, .xboxGIP, .usb),
    ] as [(UInt8, UInt8, UInt8, PhysicalProtocolID, PhysicalProtocolVariantID)]
  )
  func interfaceSignatureBindsWithoutCatalogRecord(
    signature: (UInt8, UInt8, UInt8, PhysicalProtocolID, PhysicalProtocolVariantID)
  ) throws {
    let interface = usbInterface(0, signature.0, signature.1, signature.2)
    let binding = try bound(classify(unknownDevice([interface]), backend: .rawUSB))
    #expect(binding.protocolID == signature.3)
    #expect(binding.variant == signature.4)
    #expect(binding.interfaceNumber == 0)
    #expect(binding.rule == .interfaceSignature)
    #expect(binding.matchedPredicates == [.interfaceSignature, .interruptEndpointPair])
    #expect(binding.record == nil)
  }

  @Test
  func xusbSignatureDoesNotRequireInterfaceZero() throws {
    let binding = try bound(
      classify(unknownDevice([usbInterface(2, 0xFF, 0x5D, 0x81)]), backend: .rawUSB)
    )
    #expect(binding.protocolID == .xboxXUSB)
    #expect(binding.interfaceNumber == 2)
  }

  @Test
  func gipBindsOnlyItsDataInterface() throws {
    // Xbox One controllers repeat FF/47/D0 on their audio and bulk interfaces.
    let audio = usbInterface(1, 0xFF, 0x47, 0xD0, endpoints: [])
    let binding = try bound(classify(unknownDevice([audio, gipInterface()]), backend: .rawUSB))
    #expect(binding.interfaceNumber == 0)

    #expect(
      classify(unknownDevice([usbInterface(1, 0xFF, 0x47, 0xD0)]), backend: .rawUSB)
        == rejection(.interfaceContractMismatch, .xboxGIP)
    )
  }

  @Test
  func signatureWithoutInterruptPairIsContractMismatch() {
    let shapes: [[PhysicalEndpointSignature]] = [
      [], [endpoint(0x81, .in)], [endpoint(0x01, .out)],
      [endpoint(0x81, .in, .bulk), endpoint(0x01, .out, .bulk)],
      [PhysicalEndpointSignature(direction: .in, transferType: .interrupt), endpoint(0x01, .out)],
    ]
    for endpoints in shapes {
      #expect(
        classify(
          unknownDevice([usbInterface(0, 0xFF, 0x5D, 0x01, endpoints: endpoints)]),
          backend: .rawUSB
        ) == rejection(.interfaceContractMismatch, .xboxXUSB)
      )
    }
  }

  @Test
  func signatureValidationFailureDoesNotFallThroughToHIDDescriptor() {
    let xusb = usbInterface(0, 0xFF, 0x5D, 0x01, endpoints: [endpoint(0x81, .in)])
    let hid = hidInterface(host: .usb, descriptor: gamepad)
    #expect(
      classify(unknownDevice([xusb, hid]), backend: .hid)
        == rejection(.unsupportedTransportVariant, .xboxXUSB)
    )
    #expect(
      classify(unknownDevice([xusb, hid]), backend: .rawUSB)
        == rejection(.interfaceContractMismatch, .xboxXUSB)
    )
  }

  @Test
  func proprietarySignatureOnIOHIDIsUnsupportedAndNeverGenericHID() {
    let xusb = usbInterface(0, 0xFF, 0x5D, 0x01)
    #expect(
      classify(
        unknownDevice([xusb, hidInterface(host: .usb, descriptor: gamepad)]),
        backend: .hid
      ) == rejection(.unsupportedTransportVariant, .xboxXUSB)
    )
  }

  @Test
  func twoSignatureFamiliesAreAmbiguous() {
    let result = classify(
      unknownDevice([usbInterface(0, 0xFF, 0x47, 0xD0), usbInterface(1, 0xFF, 0x5D, 0x01)]),
      backend: .rawUSB
    )
    #expect(result == .conflict(.ambiguousProtocolMatch, candidates: [.xboxGIP, .xboxXUSB]))
  }

  @Test
  func signatureOrderFollowsInterfaceNumbersNotArrayOrder() {
    let result = classify(
      unknownDevice([usbInterface(1, 0xFF, 0x5D, 0x01), usbInterface(0, 0xFF, 0x47, 0xD0)]),
      backend: .rawUSB
    )
    #expect(result == .conflict(.ambiguousProtocolMatch, candidates: [.xboxGIP, .xboxXUSB]))
  }

  @Test
  func unknownVendorInterfaceOnRawUSBHasNoMatch() {
    #expect(
      classify(unknownDevice([usbInterface(0, 0xFF, 0x5D, 0x02)]), backend: .rawUSB)
        == .unsupported(.noProtocolMatch)
    )
    #expect(classify(unknownDevice([]), backend: .usbExtension) == .unsupported(.noProtocolMatch))
  }

  @Test
  func hidInterfaceOnRawUSBIsNeverGenericHID() {
    #expect(
      classify(unknownDevice([hidInterface(host: .usb, descriptor: gamepad)]), backend: .rawUSB)
        == .unsupported(.noProtocolMatch)
    )
  }

  // MARK: - HID descriptor

  @Test
  func validDescriptorWithoutRecordBindsHIDDescriptor() throws {
    let binding = try bound(
      classify(
        unknownDevice([hidInterface(host: .bluetoothLE, descriptor: gamepad)]),
        backend: .hid
      )
    )
    #expect(binding.protocolID == .hidDescriptor)
    #expect(binding.variant == nil)
    #expect(binding.accessBackend == .hid)
    #expect(binding.rule == .hidDescriptor)
    #expect(binding.matchedPredicates == [.hidDescriptorContract])
    #expect(binding.record == nil)
  }

  @Test
  func failedDescriptorContractIsDescriptorMismatch() {
    for interfaces in [
      [hidInterface(host: .usb, descriptor: nil)],
      [hidInterface(host: .usb, descriptor: vendorOnly)], [],
    ] {
      #expect(
        classify(unknownDevice(interfaces), backend: .hid)
          == .unsupported(.descriptorContractMismatch)
      )
    }
  }

  @Test
  func hidInterfaceNumberIsRecordedWithoutChangingBinding() throws {
    func hidDevice(
      _ vendorID: UInt16,
      _ productID: UInt16,
      interface number: UInt8?
    ) -> PhysicalDevice {
      let interface = hidInterface(host: .usb, descriptor: gamepad)
      return PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: number,
            interfaceClass: interface.interfaceClass,
            hostTransport: interface.hostTransport,
            accessBackend: interface.accessBackend,
            hidLayout: interface.hidLayout
          )
        ]
      )
    }
    for (vendorID, productID) in [(0x054C, 0x09CC), (0x1234, 0x5678)] as [(UInt16, UInt16)] {
      let unnumbered = try bound(
        classify(hidDevice(vendorID, productID, interface: nil), backend: .hid)
      )
      let numbered = try bound(
        classify(hidDevice(vendorID, productID, interface: 1), backend: .hid)
      )
      #expect(numbered.interfaceNumber == 1)
      #expect(numbered.protocolID == unnumbered.protocolID)
      #expect(numbered.variant == unnumbered.variant)
      #expect(numbered.rule == unnumbered.rule)
      #expect(numbered.matchedPredicates == unnumbered.matchedPredicates)
    }
  }

  // MARK: - Helpers
}
