import Foundation
import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

/// The `session.startup` writes of a mode, the reports they send, and the transports they apply to.
struct ControllerRecordStartupWriteTests {
  private static let sixaxis = #"{"family": "SonySixaxis"}"#

  /// The `modes` field of a record whose default mode runs `protocolInfo` with `session`.
  private static func modes(_ protocolInfo: String, _ session: String? = nil) -> String {
    let session = session.map { ", \"session\": \($0)" } ?? ""
    return """
      "modes": [{"id": "default", "protocol": \(protocolInfo)\(session)}]
      """
  }

  private static func startup(_ writes: String, _ protocolInfo: String = sixaxis) -> String {
    modes(protocolInfo, "{\"startup\": \(writes)}")
  }
  private static let enable = #"""
    {"report": {"kind": "Feature", "id": 244, "length": 5}, "bytes": "42 03 00 00",
      "transport": "BluetoothClassic"}
    """#

  @Test
  func decodesStartupWritesInOrder() throws {
    let document = try decode(
      Self.startup(
        "[\(Self.enable), "
          + #"{"report": {"kind": "Output", "id": 0, "length": 2}, "bytes": "01 02", "#
          + #""delayMilliseconds": 50}]"#
      )
    )
    let session = document.baseMode.session
    #expect(session.rumbleTemplate == nil)
    #expect(session.startupWrites.count == 2)
    let enable = session.startupWrites[0]
    #expect(enable.transport == .bluetoothClassic && enable.delayMilliseconds == nil)
    #expect(
      enable.write
        == .hidFeature(PhysicalHIDOutputReport(reportID: 0xF4, bytes: [0xF4, 0x42, 3, 0, 0]))
    )
    let unnumbered = session.startupWrites[1]
    #expect(unnumbered.transport == nil && unnumbered.delayMilliseconds == 50)
    #expect(
      unnumbered.write
        == .hidOutput(
          PhysicalHIDOutputReport(reportID: 0, bytes: [1, 2], startupDelayMilliseconds: 50)
        )
    )
    #expect(try decode(Self.modes(Self.sixaxis)).baseMode.session.startupWrites.isEmpty)
  }

  @Test(
    arguments: [
      #"[]"#,
      #"[{"report": {"kind": "input", "id": 1, "length": 3}, "bytes": "00 00"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 00 00"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 100"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 -1"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 00", "#
        + #""delayMilliseconds": 1001}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 00", "#
        + #""transport": "ProprietaryRadioReceiver"}]"#,
      #"[{"report": {"kind": "Feature", "id": 1, "length": 3}, "bytes": "00 00", "repeat": 2}]"#,
      "["
        + Array(
          repeating: #"{"report": {"kind": "Feature", "id": 1, "length": 2}, "bytes": "00"}"#,
          count: 17
        )
        .joined(separator: ", ") + "]",
    ]
  )
  func rejectsInvalidStartupWrites(startup: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.startup(startup))
    }
  }

  private static let hidReport =
    #""report": {"kind": "Output", "id": 1, "length": 8}, "bytes": "01 02 03 04 05 06 07""#
  private static let gip = #"{"family": "XboxGIP"}"#

  @Test
  func decodesPhaseAndCRCSeed() throws {
    let document = try decode(
      Self.startup(
        "[{\(Self.hidReport), \"phase\": \"Startup\", " + #""crc32Seed": 162}]"#
      )
    )
    let writes = document.baseMode.session.startupWrites
    #expect(writes.first?.phase == .startup)
    #expect(writes.first?.crc32Seed == 162)
    #expect(
      try decode(Self.startup("[\(Self.enable)]")).baseMode.session.startupWrites
        .first?.phase == .activation
    )
  }

  @Test(
    arguments: [
      #""phase": "Later""#, #""crc32Seed": 256"#, #""crc32Seed": -1"#, #""delayMilliseconds": -1"#,
      #""variants": ["BluetoothClassic"]"#,
      #""when": {"parameter": "layout", "is": ["Pro"]}"#,
    ]
  )
  func rejectsAMalformedOrDescriptionOnlyHIDField(field: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.startup("[{\(Self.hidReport), \(field)}]"))
    }
  }

  @Test
  func rejectsACRCWriteWithoutRoomForTheTrailer() {
    #expect(throws: DecodingError.self) {
      try decode(
        Self.startup(
          #"[{"report": {"kind": "Output", "id": 1, "length": 4}, "bytes": "01 02 03", "#
            + #""crc32Seed": 1}]"#
        )
      )
    }
  }

  @Test
  func decodesRawUSBStartupWritesForTheFamiliesThatCarryThem() throws {
    let write =
      #"{"bytes": "01 02", "endpoint": 2, "timeoutMilliseconds": 500, "#
      + #""delayMilliseconds": 5, "sessionByte": 1, "toleratesRejection": true}"#
    for family in [Self.gip, #"{"family": "NintendoSwitch2"}"#] {
      let session = try decode(Self.startup("[\(write)]", family)).baseMode.session
      #expect(session.startupWrites.isEmpty)
      #expect(session.usbStartupWrites.count == 1)
      #expect(session.usbStartupWrites.first?.endpoint == 2)
    }
  }

  @Test(
    arguments: [
      #""endpoint": 0"#, #""endpoint": 128"#, #""timeoutMilliseconds": 0"#,
      #""timeoutMilliseconds": 60001"#, #""delayMilliseconds": 1001"#, #""sessionByte": 64"#,
      #""variants": ["USB"]"#, #""when": {"parameter": "layout", "is": ["Pro"]}"#,
    ]
  )
  func rejectsAMalformedRawUSBStartupWrite(field: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.startup(#"[{"bytes": "01", \#(field)}]"#, Self.gip))
    }
  }

  @Test
  func rejectsRawUSBStartupWritesWhereTheFamilyDoesNotCarryThem() {
    for family in [
      #"{"family": "SonySixaxis"}"#, #"{"family": "VendorGameSir", "variant": "USB"}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try decode(Self.startup(#"[{"bytes": "01"}]"#, family))
      }
    }
  }

  @Test
  func rejectsRawUSBStartupWritesNextToInitializationOrHIDWrites() {
    #expect(throws: DecodingError.self) {
      try decode(
        Self.startup(
          #"[{"bytes": "01"}]"#,
          #"{"family": "XboxGIP", "initialization": ["XboxGIP/power-on"]}"#
        )
      )
    }
    #expect(throws: DecodingError.self) {
      try decode(Self.startup(#"[{"bytes": "01"}, {\#(Self.hidReport)}]"#, Self.gip))
    }
  }

  @Test
  func rejectsAnEmptySession() {
    #expect(throws: DecodingError.self) { try decode(Self.modes(Self.sixaxis, "{}")) }
  }

  /// Startup writes go through IOHID, so a raw-USB family cannot name them.
  @Test(
    arguments: [
      #"{"family": "XboxGIP"}"#, #"{"family": "XboxXUSB", "variant": "Wired"}"#,
      #"{"family": "VendorGameSir", "variant": "USB"}"#,
    ]
  )
  func rejectsStartupWritesOnRawUSBFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.startup("[\(Self.enable)]", protocolInfo))
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

  /// Both Sixaxis identities carry the Bluetooth enable report `hid-sony.c` sends, in the
  /// `bluetooth` mode that a Bluetooth link selects; the default mode sends nothing.
  @Test(arguments: [UInt16(0x0268), 0x0523])
  func sixaxisRecordsEnableBluetooth(productID: UInt16) async throws {
    let vendorID: UInt16 = productID == 0x0268 ? 0x054C : 0x2563
    let model = ControllerModelID(vendorID: vendorID, productID: productID)
    let base = try #require(DeviceCatalog().record(for: model))
    #expect(base.startupWrites.isEmpty)
    let record = try #require(DeviceCatalog().record(for: model, modeID: "bluetooth"))
    #expect(record.physicalProtocolID == .sonySixaxis)
    #expect(record.startupWrites.map(\.transport) == [nil])
    func device(_ link: PhysicalTransport) -> PhysicalDevice {
      PhysicalDevice(
        vendorID: vendorID,
        productID: productID,
        interfaces: [PhysicalInterfaceSignature(interfaceNumber: 0, hostTransport: link)]
      )
    }
    // The DS3 also has a probed mode, which a wired link reaches and the reader cannot answer.
    for (link, expected) in [(PhysicalTransport.bluetoothClassic, "bluetooth"), (.usb, nil)] {
      let selected = await ControllerModeSelector.select(
        from: base,
        model: model,
        backend: .hid,
        reader: UnansweredProbeReader(),
        device: device(link)
      ) { _ in }
      #expect(selected.modeID == expected)
    }
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
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 9571, "productID": 1397, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}

/// A reader that never answers, so a probed mode is never selected.
private struct UnansweredProbeReader: ControllerModeProbeReader {
  func readFeatureReport(
    _: PhysicalHIDFeatureReadRequest
  ) -> PhysicalHIDReportResult<Data> {
    return .unavailable
  }
}
