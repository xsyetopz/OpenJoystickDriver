import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The next step that `ojd controller show` and the Controllers detail give for a connected
/// device that OJD does not serve.
struct UnservedDeviceNextStepTests {
  private static func unbound(
    _ reason: ProtocolBindingReason,
    backend: DeviceAccessBackend,
    interfaces: [ProtocolBindingResult.InterfaceSummary] = []
  ) -> ApplicationServiceUnboundDevice {
    ApplicationServiceUnboundDevice(
      vendorID: 0x3537,
      productID: 0x1010,
      connection: "USB",
      accessBackend: backend,
      reason: reason,
      rejectedCandidates: [],
      interfaces: interfaces
    )
  }

  private static let gamepad = ProtocolBindingResult.InterfaceSummary(
    PhysicalInterfaceSignature(
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .usb,
      accessBackend: .hid,
      hidLayout: HIDLayoutSummary(
        hasGamePadOrJoystickCollection: true,
        primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5)
      )
    )
  )

  @Test
  func identityIsTheHexPairOjdPrints() {
    #expect(Self.unbound(.noProtocolMatch, backend: .rawUSB).identity == "3537:1010")
  }

  @Test
  func aHIDGamepadOffersTheDraftCommand() {
    let pad = Self.unbound(.descriptorContractMismatch, backend: .hid, interfaces: [Self.gamepad])
    #expect(pad.isHIDGamepad)
    #expect(pad.draftCommand == "ojd record draft 3537:1010")
  }

  @Test
  func aDeviceWithoutAHIDGamepadOffersNoDraft() {
    #expect(Self.unbound(.noProtocolMatch, backend: .rawUSB).draftCommand == nil)
    #expect(Self.unbound(.noProtocolMatch, backend: .hid).draftCommand == nil)
    let raw = Self.unbound(.deviceInUse, backend: .rawUSB, interfaces: [Self.gamepad])
    #expect(raw.draftCommand == nil)
  }

  @Test
  func onlyNoProtocolMatchOffersTheCaptureCommand() {
    for reason in ProtocolBindingReason.allCases {
      let command = Self.unbound(reason, backend: .rawUSB).captureCommand
      if reason == .noProtocolMatch {
        #expect(command == "ojd controller capture 3537:1010 --duration 10 --json > capture.jsonl")
      } else {
        #expect(command == nil, "\(reason)")
      }
    }
  }
}
