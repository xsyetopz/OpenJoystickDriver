import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The ZD Ultimate Legend, issue #22: the wired pad `413D:2104` and its 2.4 GHz dongle `413D:2204`.
///
/// The bytes are the reporters' own. `lunarephemera` captured the wired pad's endpoint `0x81` and
/// `gornobatov` read the dongle's HID report descriptor from the kernel log.
struct ZDUltimateLegendRecordTests {
  private static let wired = ControllerModelID(vendorID: 0x413D, productID: 0x2104)
  private static let dongle = ControllerModelID(vendorID: 0x413D, productID: 0x2204)

  /// One input report of the wired pad, as `lunarephemera` captured it.
  private static let capturedReport: [UInt8] = [
    0x00, 0x14, 0x00, 0x00, 0x00, 0x00, 0x35, 0x77, 0xE9, 0xC2, 0x77, 0xEB, 0x22, 0xDC, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00,
  ]

  /// Bytes 2 and 3 of each control's report, from the reporter's 16 of 16 table.
  private static let controlBytes: [(control: Control?, hat: HatDirection, bytes: [UInt8])] = [
    (nil, .north, [0x01, 0x00]), (nil, .south, [0x02, 0x00]),
    (nil, .west, [0x04, 0x00]), (nil, .east, [0x08, 0x00]),
    (.start, .neutral, [0x10, 0x00]), (.back, .neutral, [0x20, 0x00]),
    (.leftStickClick, .neutral, [0x40, 0x00]), (.rightStickClick, .neutral, [0x80, 0x00]),
    (.leftShoulder, .neutral, [0x00, 0x01]), (.rightShoulder, .neutral, [0x00, 0x02]),
    (.guide, .neutral, [0x00, 0x04]), (.south, .neutral, [0x00, 0x10]),
    (.east, .neutral, [0x00, 0x20]), (.west, .neutral, [0x00, 0x40]),
    (.north, .neutral, [0x00, 0x80]),
  ]

  private func wiredRecord() throws -> ControllerRecord {
    try #require(ControllerRecordSet.bundled.records[Self.wired])
  }

  @Test
  func theWiredPadReadsTheCapturedReportAsNoButtonAndNoTrigger() throws {
    let state = try wiredRecord().replay(reports: [Self.capturedReport]).state
    #expect(state.pressed.isEmpty)
    #expect(state.hat == .neutral)
    #expect(state.leftTrigger == .min)
    #expect(state.rightTrigger == .min)
  }

  @Test
  func theWiredPadMapsEveryReportedControlLikeTheWiredXbox360() throws {
    let record = try wiredRecord()
    for entry in Self.controlBytes {
      var report = [UInt8](repeating: 0, count: 20)
      report[1] = 0x14
      report[2] = entry.bytes[0]
      report[3] = entry.bytes[1]
      let state = try record.replay(reports: [report]).state
      #expect(state.hat == entry.hat, "bytes \(entry.bytes)")
      #expect(state.pressed == Set(entry.control.map { [$0] } ?? []), "bytes \(entry.bytes)")
    }
  }

  @Test
  func theWiredPadSendsRumbleAndTheIndicatorToOutEndpoint0x02() throws {
    let transport = try wiredRecord().profile.transportProfile
    #expect(transport.inputEndpoint == 0x81)
    #expect(transport.outputEndpoint == 0x02)
    #expect(transport.hasEndpointOverride)
    #expect(transport.interfaceNumber == 0)
  }

  /// The issue gives the dongle no interface protocol and no endpoint, and the signature tests of
  /// `SameIdentityDongleTests` bind both shapes, so a fixed `Receiver` or `Wired` record would
  /// break one of them.
  @Test
  func theDongleHasNoBundledRecordUntilItsXInputInterfaceIsCaptured() {
    #expect(ControllerRecordSet.bundled.records[Self.dongle] == nil)
  }

  /// The HID interface of the dongle, from the kernel log: a vendor page with one 64-byte input and
  /// one 64-byte output and no Generic Desktop usage, so a `HIDDescriptor` mode cannot read a pad
  /// from it.
  @Test
  func theDonglesHIDDescriptorIsVendorDefinedWithNoGamepadUsage() throws {
    let descriptor = try #require(
      Data(base64Encoded: "Bnr/CQGhAQkCoQAJAxUAJf91CJVAgQIJBZECwMA=")
    )
    #expect(
      Array(descriptor) == [
        0x06, 0x7A, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x09, 0x02, 0xA1, 0x00, 0x09, 0x03, 0x15, 0x00,
        0x25, 0xFF, 0x75, 0x08, 0x95, 0x40, 0x81, 0x02, 0x09, 0x05, 0x91, 0x02, 0xC0, 0xC0,
      ]
    )
  }
}
