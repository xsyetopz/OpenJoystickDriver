import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct MicrosoftOSDescriptorTests {
  /// An OS string descriptor: length 18, type STRING, "MSFT100", vendor code 0x90, pad.
  private static let osString: [UInt8] =
    [0x12, 0x03] + MicrosoftOSDescriptor.signature + [0x90, 0x00]

  /// An extended compat ID descriptor with one section, interface 0, compatible ID "XGIP10".
  private static let compatID: [UInt8] =
    [0x28, 0, 0, 0, 0x00, 0x01, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0]
    + [0x00, 0x01] + Array("XGIP10".utf8) + [0, 0] + [UInt8](repeating: 0, count: 14)

  @Test
  func requestsMatchTheWindowsSetupPackets() throws {
    let configuration = try MicrosoftOSDescriptor.configurationRequest()
    let string = try MicrosoftOSDescriptor.stringRequest()
    let compat = try MicrosoftOSDescriptor.compatIDRequest(vendorCode: 0x90, length: 16)

    #expect(
      [configuration.requestType, configuration.request] == [0x80, 0x06]
        && [configuration.value, configuration.length] == [0x0200, 255]
    )
    #expect(string.value == 0x03EE && string.length == 18)
    #expect(
      [compat.requestType, compat.request] == [0xC0, 0x90]
        && [compat.index, compat.length] == [4, 16]
    )
  }

  @Test
  func signedOSStringNamesItsVendorCode() {
    #expect(MicrosoftOSDescriptor.vendorCode(fromString: Self.osString) == 0x90)
  }

  @Test(arguments: [
    Array(osString.prefix(17)),
    [0x12, 0x02] + osString.dropFirst(2),
    osString.enumerated().map { $0.offset == 4 ? 0x58 : $0.element },
  ])
  func unsignedOrShortOSStringHasNoVendorCode(descriptor: [UInt8]) {
    #expect(MicrosoftOSDescriptor.vendorCode(fromString: descriptor) == nil)
  }

  @Test
  func compatIDHeaderGivesTheFullLength() {
    #expect(MicrosoftOSDescriptor.compatIDLength(fromHeader: Array(Self.compatID.prefix(16))) == 40)
  }

  @Test(arguments: [[0x10, 0, 0, 0], [0x00, 0x00, 0x01, 0x00], [0x28, 0, 0]] as [[UInt8]])
  func headerWithNoSectionOrBeyondAControlTransferHasNoLength(header: [UInt8]) {
    #expect(MicrosoftOSDescriptor.compatIDLength(fromHeader: header) == nil)
  }

  @Test
  func compatibleIDsDropTheirPadding() {
    #expect(MicrosoftOSDescriptor.compatibleIDs(from: Self.compatID) == ["XGIP10"])
  }

  @Test
  func truncatedSectionIsSkipped() {
    #expect(MicrosoftOSDescriptor.compatibleIDs(from: Array(Self.compatID.prefix(20))).isEmpty)
  }
}
