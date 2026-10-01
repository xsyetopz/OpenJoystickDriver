import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record's `ownership` and `output` fields, the rumble template they decode into, and the
/// writes OJD keeps for a controller macOS serves.
struct ControllerRecordOutputTests {
  private static let thirdParty = #""protocol": {"family": "vendor.ps3-third-party"}"#
  private static let gp100Rumble = #"""
    "rumble": {"report": {"kind": "output", "id": 2, "length": 8},
      "leftMain": {"byte": 3}, "rightMain": {"byte": 2}}
    """#

  @Test
  func decodesOwnershipAndARumbleTemplate() throws {
    let document = try decode(
      "\(Self.thirdParty), \"ownership\": \"ojd\", \"output\": {\(Self.gp100Rumble)}"
    )
    #expect(document.ownership == .ojd)
    let template = try #require(document.rumbleTemplate)
    #expect(template.report == ControllerTemplateReport(kind: .output, reportID: 2, length: 8))
    #expect(template.motorBytes == [.leftMain: 3, .rightMain: 2])
    #expect(template.outputCapabilities == .dualMainRumble)
    #expect(try decode(Self.thirdParty).ownership == nil)
    let sixaxis = try decode(#""protocol": {"family": "sony.sixaxis"}, "ownership": "macos""#)
    #expect(sixaxis.ownership == .macOS)
  }

  @Test(arguments: ["OJD", "native", ""])
  func rejectsUnknownOwnership(name: String) {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.thirdParty), \"ownership\": \"\(name)\"")
    }
  }

  /// macOS cannot serve a raw-USB family, so the record has no ownership to choose.
  @Test(
    arguments: [
      #"{"family": "xbox.gip"}"#, #"{"family": "xbox.xusb", "variant": "wired"}"#,
      #"{"family": "vendor.gamesir", "variant": "usb"}"#,
    ]
  )
  func rejectsOwnershipOnRawUSBFamilies(protocolInfo: String) {
    #expect(throws: DecodingError.self) {
      try decode("\"protocol\": \(protocolInfo), \"ownership\": \"ojd\"")
    }
  }

  @Test(arguments: PhysicalProtocolID.allCases.filter { !$0.encodesRumbleTemplate })
  func rejectsTemplatesForDriversThatDoNotEncodeThem(family: PhysicalProtocolID) {
    let variant = family.storesVariant ? family.variants.first?.rawValue : nil
    let protocolInfo =
      variant.map { "{\"family\": \"\(family.rawValue)\", \"variant\": \"\($0)\"}" }
      ?? "{\"family\": \"\(family.rawValue)\"}"
    #expect(throws: DecodingError.self) {
      try decode("\"protocol\": \(protocolInfo), \"output\": {\(Self.gp100Rumble)}")
    }
  }

  @Test(
    arguments: [
      #"{"report": {"kind": "input", "id": 2, "length": 8}, "leftMain": {"byte": 3}}"#,
      #"{"report": {"kind": "output", "id": 256, "length": 8}, "leftMain": {"byte": 3}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 1}, "leftMain": {"byte": 0}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 65}, "leftMain": {"byte": 3}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}, "leftMain": {"byte": 0}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}, "leftMain": {"byte": 8}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}, "leftMain": {"byte": 3}, "#
        + #""rightMain": {"byte": 3}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}, "leftMain": {"byte": 3, "max": 9}}"#,
      #"{"report": {"kind": "output", "id": 2, "length": 8}, "leftHaptic": {"byte": 3}}"#,
    ]
  )
  func rejectsInvalidRumbleTemplates(rumble: String) {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.thirdParty), \"output\": {\"rumble\": \(rumble)}")
    }
  }

  @Test
  func rejectsUnknownOutputTemplates() {
    #expect(throws: DecodingError.self) {
      try decode("\(Self.thirdParty), \"output\": {\(Self.gp100Rumble), \"lighting\": {}}")
    }
  }

  /// A report ID of 0 has no ID byte, so byte 0 carries a motor; a feature report stays a feature.
  @Test
  func writesReportsWithoutAnIDAndFeatureReports() throws {
    let unnumbered = try RumbleOutputTemplate(
      report: ControllerTemplateReport(kind: .output, reportID: 0, length: 4),
      motorBytes: [.leftMain: 0, .rightTrigger: 3]
    )
    let intensities = RumbleIntensities(
      leftMain: UnipolarValue(byte: 0x11),
      rightMain: UnipolarValue(byte: 0x22),
      rightTrigger: UnipolarValue(byte: 0x33)
    )
    guard case .hidOutput(let report) = unnumbered.write(intensities) else {
      Issue.record("expected an output report")
      return
    }
    #expect(report.reportID == 0)
    #expect(report.bytes == [0x11, 0, 0, 0x33])

    let feature = try RumbleOutputTemplate(
      report: ControllerTemplateReport(kind: .feature, reportID: 5, length: 3),
      motorBytes: [.rightMain: 1]
    )
    guard case .hidFeature(let featureReport) = feature.write(intensities) else {
      Issue.record("expected a feature report")
      return
    }
    #expect(featureReport.bytes == [5, 0x22, 0])
  }

  /// Sixaxis keeps its family writes; a record template adds exactly its own report.
  @Test
  func macOSOwnedOutputAddsOnlyTheRecordReport() throws {
    let sixaxis = MacOSOwnedOutput.allowance(for: .sonySixaxis, record: nil)
    let sixaxisReport = PhysicalHIDOutputReport(
      reportID: 1,
      bytes: [1] + [UInt8](repeating: 0, count: 48)
    )
    #expect(sixaxis.permits(sixaxisReport, kind: .output))
    #expect(!sixaxis.permits(sixaxisReport, kind: .feature))
    #expect(!sixaxis.permits(PhysicalHIDOutputReport(reportID: 1, bytes: [1, 0]), kind: .output))
    #expect(sixaxis.setsStartupPlayerIndicator && sixaxis.readsStartupFeatures)

    #expect(MacOSOwnedOutput.allowance(for: .hidReportLayout, record: nil) == .none)
    let gp100 = try #require(
      DeviceCatalog().record(for: DeviceIdentifier(vendorID: 0x2563, productID: 0x0575))
    )
    let allowance = MacOSOwnedOutput.allowance(for: .hidReportLayout, record: gp100)
    let rumble = PhysicalHIDOutputReport(reportID: 2, bytes: [2, 0, 0, 0, 0, 0, 0, 0])
    #expect(allowance.drivesRumble)
    #expect(allowance.permits(rumble, kind: .output))
    #expect(!allowance.permits(PhysicalHIDOutputReport(reportID: 2, bytes: [2, 0]), kind: .output))
    #expect(!allowance.permits(sixaxisReport, kind: .output))
    #expect(!allowance.setsStartupPlayerIndicator && !allowance.readsStartupFeatures)
    #expect(allowance.narrowing(.dualMainRumble) == .dualMainRumble)
    #expect(MacOSOwnedOutput.none.narrowing(.dualMainRumble) == .none)
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
