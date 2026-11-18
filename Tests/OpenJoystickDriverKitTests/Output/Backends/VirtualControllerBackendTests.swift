import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct VirtualControllerBackendTests {
  @Test
  func testGameControllerHIDBackendCapability() {
    let capabilities = VirtualControllerBackendCatalog.gameControllerHIDCapabilities

    #expect(capabilities.isImplemented)
    #expect(capabilities.isSystemWide)
    #expect(capabilities.publishesConsumerGamepad)
    #expect(VirtualControllerBackendID.allCases.contains(.gameControllerHID))
    #expect(!capabilities.notes.isEmpty)
  }

  @Test
  func testUserSpaceSerialUsesStableHashedPhysicalIdentity() {
    let identifier = LogicalControllerID(
      vendorID: 13623,
      productID: 4112,
      serialNumber: "physical-serial"
    )
    let serial = UserSpaceVirtualDeviceConstants.serialNumber(for: identifier)

    #expect(serial.hasPrefix(UserSpaceVirtualDeviceConstants.serialPrefix))
    #expect(serial.count == UserSpaceVirtualDeviceConstants.serialPrefix.count + 16)
    #expect(serial.suffix(16).allSatisfy { $0.isHexDigit })
    #expect(serial == UserSpaceVirtualDeviceConstants.serialNumber(for: identifier))
  }

  @Test
  func nonStandardButtonsKeepDistinctNormalizedBits() {
    func bit(_ control: Control) -> UInt32? {
      VirtualGamepadReportMapping.buttonBit(for: control)
    }

    #expect(bit(.capture) == 15)
    #expect(bit(.back) == 9)
    #expect(bit(.start) == 8)
    // A pad click is R3 only where the right pad is the right stick (PersonaControlMappingTests).
    #expect(bit(.rightStickClick) == 7)
    #expect(bit(.rightTrackpadClick) == nil)
    #expect(bit(.microphone) == nil)
    #expect(bit(.touchpadClick) == nil)
  }

  @Test
  func testXboxOneVirtualOutputFormatDeclaresRumbleOutputSize() {
    let format = XboxOneGIPHIDReportFormat()

    #expect(format.inputReportID == 0x20)
    #expect(format.outputReportID == ConsumerOutputCodec.xboxOneReportID)
    #expect(format.outputReportPayloadSize == ConsumerOutputCodec.xboxOneReportPayloadSize)
  }

  @Test
  func testVirtualOutputFormatsReturnFullyNeutralReportsAfterRelease() {
    let generic = OJDGenericGamepadFormat().buildInputReport(from: VirtualGamepadState())
    let xone = XboxOneGIPHIDReportFormat().buildInputReport(from: VirtualGamepadState())

    #expect(generic == [UInt8](repeating: 0, count: generic.count))
    #expect(xone == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
  }

  @Test
  func userSpaceCreationErrorsDistinguishPermissionFromEntitlementAndCreation() {
    let errors: [UserSpaceOutputDispatcher.CreationError] = [
      .inputReadDenied, .inputInjectDenied, .createFailed, .missingEntitlement("test"),
    ]
    for error in errors {
      switch error {
      case .inputReadDenied, .inputInjectDenied, .createFailed, .missingEntitlement: break
      }
    }
  }
}
