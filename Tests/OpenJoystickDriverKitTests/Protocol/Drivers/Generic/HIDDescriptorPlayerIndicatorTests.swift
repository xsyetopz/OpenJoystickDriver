import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The player-indicator template of a `HIDDescriptor` record, which the driver encodes into a HID
/// report, and the allowance that lets OJD send it while macOS serves the controller.
struct HIDDescriptorPlayerIndicatorTests {
  private static let model = ControllerModelID(vendorID: 0x0111, productID: 0x1420)
  private static let report = ControllerTemplateReport(kind: .output, reportID: 0, length: 1)
  private static let bytes: [PhysicalPlayerIndicator: UInt8] = [
    .off: 0, .player1: 1, .player2: 2, .player3: 4, .player4: 8,
  ]

  private static func template(
    report: ControllerTemplateReport = report,
    byte: Int = 0,
    values: [PhysicalPlayerIndicator: UInt8] = bytes
  ) throws -> PlayerIndicatorOutputTemplate {
    try PlayerIndicatorOutputTemplate(report: report, byte: byte, values: values)
  }

  @Test
  func driverWithoutTemplateHasNoPlayerIndicator() {
    let driver = HIDDescriptorDriver(model: Self.model)
    #expect(driver.outputCapabilities == .none)
    #expect(throws: ControllerOutputError.self) {
      try driver.encode(.setPlayerIndicator(.player1))
    }
  }

  @Test(arguments: PhysicalPlayerIndicator.allCases)
  func encodesEachSlotIntoItsByte(slot: PhysicalPlayerIndicator) throws {
    let driver = HIDDescriptorDriver(
      model: Self.model,
      usageMap: nil,
      playerIndicatorTemplate: try Self.template()
    )
    #expect(driver.outputCapabilities.lightingFeatures == [.playerIndicator])
    let writes = try driver.encode(.setPlayerIndicator(slot)).writes
    guard case .hidOutput(let report)? = writes.first else {
      Issue.record("no HID output report: \(writes)")
      return
    }
    #expect(report.reportID == 0)
    #expect(report.bytes == [try #require(Self.bytes[slot])])
  }

  /// A numbered report keeps its ID in byte 0 and the other bytes zero.
  @Test
  func writesNumberedFeatureReportWithZeroedRest() throws {
    let numbered = try Self.template(
      report: ControllerTemplateReport(kind: .feature, reportID: 5, length: 4),
      byte: 2
    )
    guard case .hidFeature(let report) = numbered.write(.player3) else {
      Issue.record("expected a feature report")
      return
    }
    #expect(report.bytes == [5, 0, 4, 0])
  }

  @Test
  func rejectsOtherCommands() throws {
    let driver = HIDDescriptorDriver(
      model: Self.model,
      usageMap: nil,
      playerIndicatorTemplate: try Self.template()
    )
    #expect(throws: ControllerOutputError.self) { try driver.encode(.stopRumble) }
  }

  @Test
  func rejectsInvalidTemplates() {
    #expect(throws: ControllerRecordProblem.self) {
      try Self.template(byte: 1)
    }
    #expect(throws: ControllerRecordProblem.self) {
      try Self.template(
        report: ControllerTemplateReport(kind: .output, reportID: 3, length: 2),
        byte: 0
      )
    }
    #expect(throws: ControllerRecordProblem.self) {
      try Self.template(report: ControllerTemplateReport(kind: .input, reportID: 0, length: 1))
    }
    #expect(throws: ControllerRecordProblem.self) {
      try Self.template(values: [.off: 0, .player1: 1])
    }
  }

  /// The player report joins the allowance, so the write executors send it and the slot is set
  /// after the first input report.
  @Test
  func allowanceCoversPlayerReport() throws {
    let record = try #require(DeviceCatalog().record(for: Self.model))
    #expect(record.playerIndicatorTemplate != nil)
    let allowance = MacOSOwnedOutput.allowance(for: .hidDescriptor, record: record)
    #expect(allowance.permits(PhysicalHIDOutputReport(reportID: 0, bytes: [1]), kind: .output))
    #expect(!allowance.permits(PhysicalHIDOutputReport(reportID: 0, bytes: [1, 0]), kind: .output))
    #expect(allowance.lightingFeatures.contains(.playerIndicator))
    #expect(allowance.setsStartupPlayerIndicator)
    #expect(!allowance.drivesRumble)
    let capabilities = PhysicalControllerOutputCapabilities(lightingFeatures: [.playerIndicator])
    #expect(allowance.narrowing(capabilities) == capabilities)
  }

  // MARK: Record decoding

  private static func modes(family: String, playerIndicator: String) -> String {
    """
    "modes": [{"id": "default", "protocol": {"family": "\(family)"}, \
    "session": {"playerIndicator": \(playerIndicator)}}]
    """
  }

  private static let valid = #"""
    {"report": {"kind": "Output", "id": 0, "length": 1}, "byte": 0, "off": 0, "player1": 1,
    "player2": 2, "player3": 4, "player4": 8}
    """#

  @Test
  func decodesTemplateFromRecord() throws {
    let document = try decode(Self.modes(family: "HIDDescriptor", playerIndicator: Self.valid))
    let template = try #require(document.baseMode.session.playerIndicatorTemplate)
    #expect(template.report == Self.report)
    #expect(template.values == Self.bytes)
    #expect(template.outputCapabilities.lightingFeatures == [.playerIndicator])
  }

  /// A template with the report, byte and slot keys given; `extra` adds a key.
  private static func json(
    report: String = #"{"kind": "Output", "id": 0, "length": 1}"#,
    byte: Int = 0,
    player3: Int = 4,
    player4: String = "8",
    extra: String = ""
  ) -> String {
    let slots = "\"off\": 0, \"player1\": 1, \"player2\": 2, \"player3\": \(player3)"
    let fourth = player4.isEmpty ? "" : ", \"player4\": \(player4)"
    return "{\"report\": \(report), \"byte\": \(byte), \(slots)\(fourth)\(extra)}"
  }

  private static let invalidTemplates: [String] = [
    json(byte: 1),
    json(report: #"{"kind": "Input", "id": 0, "length": 1}"#),
    json(report: #"{"kind": "Output", "id": 0, "length": 0}"#),
    json(report: #"{"kind": "Output", "id": 0, "length": 65}"#),
    json(player4: ""),
    json(player4: "256"),
    json(extra: ", \"player5\": 16"),
  ]

  @Test(arguments: invalidTemplates)
  func rejectsInvalidTemplatesInRecord(template: String) {
    #expect(throws: DecodingError.self) {
      try decode(Self.modes(family: "HIDDescriptor", playerIndicator: template))
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter { $0 != .hidDescriptor })
  func rejectsTemplateForOtherDrivers(family: PhysicalProtocolID) {
    let variant = family.storesVariant ? family.variants.first?.rawValue : nil
    let protocolInfo =
      variant.map { "{\"family\": \"\(family.rawValue)\", \"variant\": \"\($0)\"}" }
      ?? "{\"family\": \"\(family.rawValue)\"}"
    #expect(throws: DecodingError.self) {
      try decode(
        "\"modes\": [{\"id\": \"default\", \"protocol\": \(protocolInfo), "
          + "\"session\": {\"playerIndicator\": \(Self.valid)}}]"
      )
    }
  }

  private func decode(_ fields: String) throws -> ControllerRecordDocument {
    let json = """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "\(ControllerRecordDocument.kind)",
      "vendorID": 273, "productID": 5152, \
      \(fields)}
      """
    return try JSONDecoder().decode(ControllerRecordDocument.self, from: Data(json.utf8))
  }
}
