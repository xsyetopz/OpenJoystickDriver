import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The record's `output.startup` writes, the reports they send, and the transports they apply to.
struct ControllerRecordStartupWriteTests {
  private static let sixaxis = #""protocol": {"family": "sony.sixaxis"}"#
  private static let enable = #"""
    {"report": {"kind": "feature", "id": 244, "length": 5}, "bytes": [66, 3, 0, 0],
      "transport": "bluetooth-classic"}
    """#

  @Test
  func decodesStartupWritesInOrder() throws {
    let document = try decode(
      "\(Self.sixaxis), \"output\": {\"startup\": [\(Self.enable), "
        + #"{"report": {"kind": "output", "id": 0, "length": 2}, "bytes": [1, 2], "#
        + #""delayMilliseconds": 50}]}"#
    )
    #expect(document.rumbleTemplate == nil)
    #expect(document.startupWrites.count == 2)
    let enable = document.startupWrites[0]
    #expect(enable.transport == .bluetoothClassic && enable.delayMilliseconds == 0)
    #expect(
      enable.write
        == .hidFeature(PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 3, 0, 0]))
    )
    let unnumbered = document.startupWrites[1]
    #expect(unnumbered.transport == nil && unnumbered.delayMilliseconds == 50)
    #expect(unnumbered.write == .hidOutput(PhysicalHIDOutputReport(reportID: 0, bytes: [1, 2])))
    #expect(try decode(Self.sixaxis).startupWrites.isEmpty)
  }

  @Test(
    arguments: [
      #"[]"#,
      #"[{"report": {"kind": "input", "id": 1, "length": 3}, "bytes": [0, 0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0, 0]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 256]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, -1]}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "#
        + #""delayMilliseconds": 1001}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "#
        + #""transport": "proprietary-radio-receiver"}]"#,
      #"[{"report": {"kind": "feature", "id": 1, "length": 3}, "bytes": [0, 0], "repeat": 2}]"#,
      "["
        + Array(
          repeating: #"{"report": {"kind": "feature", "id": 1, "length": 2}, "bytes": [0]}"#,
          count: 17
        )
        .joined(separator: ", ") + "]",
    ]
  )
  func rejectsInvalidStartupWrites(startup: String) {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.sixaxis), \"output\": {\"startup\": \(startup)}")
    }
  }

  @Test
  func rejectsAnEmptyOutputSection() {
    #expect(throws: DecodingError.self) { try decode("\(Self.sixaxis), \"output\": {}") }
  }

  /// Startup writes go through IOHID, so a raw-USB family cannot name them.
  @Test(
    arguments: [
      #"{"family": "xbox.gip"}"#, #"{"family": "xbox.xusb", "variant": "wired"}"#,
      #"{"family": "vendor.gamesir", "variant": "usb"}"#,
    ]
  )
  func rejectsStartupWritesOnRawUSBFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode("\"protocol\": \(protocolInfo), \"output\": {\"startup\": [\(Self.enable)]}")
    }
  }

  @Test
  func appliesOnlyToItsTransport() throws {
    let report = ControllerTemplateReport(kind: .feature, reportID: 1, length: 2)
    let bluetooth = try RecordStartupWrite(report: report, bytes: [0], transport: .bluetoothClassic)
    #expect(bluetooth.applies(to: .bluetoothClassic))
    #expect(!bluetooth.applies(to: .usb) && !bluetooth.applies(to: nil))
    let any = try RecordStartupWrite(report: report, bytes: [0])
    #expect(any.applies(to: .usb) && any.applies(to: .bluetoothLE) && any.applies(to: nil))
  }

  /// Both Sixaxis identities carry the Bluetooth enable report `hid-sony.c` sends.
  @Test(arguments: [UInt16(0x0268), 0x0523])
  func sixaxisRecordsEnableBluetooth(productID: UInt16) throws {
    let vendorID: UInt16 = productID == 0x0268 ? 0x054C : 0x2563
    let record = try #require(
      DeviceCatalog().record(for: DeviceIdentifier(vendorID: vendorID, productID: productID))
    )
    #expect(record.physicalProtocolID == .sonySixaxis)
    #expect(record.startupWrites.map(\.transport) == [.bluetoothClassic])
    #expect(
      record.startupWrites.map(\.write) == [
        .hidFeature(
          PhysicalHIDOutputReport(
            reportID: ProtocolPacketFixtures.DS3.bluetoothOperationalReportID,
            bytes: ProtocolPacketFixtures.DS3.bluetoothOperationalReport
          )
        )
      ]
    )
  }

  /// Decodes a record for 2563:0575 whose remaining top-level fields are `fields`.
  private func decode(_ fields: String) throws -> ControllerRecordDocument {
    let json = """
      {"$schema": "\(ControllerRecordDocument.schemaID)", "vendorID": 9571, "productID": 1397, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}
