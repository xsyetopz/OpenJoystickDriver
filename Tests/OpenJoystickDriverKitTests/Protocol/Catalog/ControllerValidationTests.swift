import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerValidationTests {
  private static let model = ControllerModelID(vendorID: 0x366C, productID: 0x0005)
  private static let unbundled = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  private static func document(validations: [[String: Any]]?) throws -> Data {
    var tree: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
      "vendorID": Int(unbundled.vendorID), "productID": Int(unbundled.productID),
      "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ]
    if let validations { tree["validations"] = validations }
    return try PropertyListFixture.data(tree: tree)
  }

  private static func validation(
    issue: Int = 12,
    mode: String = "default",
    date: String = "2026-11-14"
  ) -> [String: Any] {
    ["issue": issue, "mode": mode, "appVersion": "0.6.0", "date": date]
  }

  private static func record(validations: [[String: Any]]?) throws -> ControllerRecord {
    try #require(
      try ControllerRecordSet.validate(document(validations: validations)).record
    )
  }

  @Test
  func recordReadsItsValidations() throws {
    let record = try Self.record(validations: [Self.validation()])
    let validation = try #require(record.validation(ofMode: "default"))
    #expect(record.validations == [validation])
    #expect(validation.issue == 12)
    #expect(validation.appVersion == "0.6.0")
    #expect(validation.date == "2026-11-14")
    #expect(
      validation.issueURL.absoluteString
        == "https://github.com/xsyetopz/OpenJoystickDriver/issues/12"
    )
  }

  @Test
  func recordWithoutValidationsHasNone() throws {
    let record = try Self.record(validations: nil)
    #expect(record.validations.isEmpty)
    #expect(record.validation(ofMode: "default") == nil)
  }

  @Test
  func lastValidationOfAModeWins() throws {
    let record = try Self.record(
      validations: [Self.validation(issue: 3), Self.validation(issue: 9)]
    )
    #expect(record.validation(ofMode: "default")?.issue == 9)
  }

  @Test
  func unknownModeIsRefused() throws {
    let data = try Self.document(validations: [Self.validation(mode: "xinput")])
    do {
      _ = try ControllerRecordSet.validate(data)
      Issue.record("a validation of an unknown mode was accepted")
    } catch {
      #expect(ControllerRecordSet.problemCode(error) == .invalidControllerRecord)
      let text = ControllerRecordSet.problemDescription(error, document: "record")
      #expect(text.contains("xinput"))
    }
  }

  @Test
  func badFieldsAreRefused() throws {
    for bad in [Self.validation(issue: 0), Self.validation(date: "14.11.2026")] {
      let data = try Self.document(validations: [bad])
      #expect(throws: (any Error).self) { try ControllerRecordSet.validate(data) }
    }
  }

  @Test
  func noBundledRecordHasValidations() {
    #expect(ControllerRecordSet.bundled.records.values.allSatisfy { $0.validations.isEmpty })
  }

  @Test
  func lookupOpensThePageForARecord() throws {
    let record = try Self.record(validations: nil)
    #expect(
      ControllerLookup.url(for: Self.model, record: record).absoluteString
        == "https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers"
    )
  }

  @Test
  func lookupOpensTheVerifiedTierForAValidatedRecord() throws {
    let record = try Self.record(validations: [Self.validation()])
    #expect(
      ControllerLookup.url(for: Self.model, record: record).absoluteString
        == "https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers#community-verified"
    )
  }

  @Test
  func lookupSearchesIssuesForAModelWithoutARecord() {
    #expect(
      ControllerLookup.url(for: Self.unbundled, record: nil).absoluteString
        == "https://github.com/xsyetopz/OpenJoystickDriver/issues?q=1234:ABCD"
    )
  }
}
