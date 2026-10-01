import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The record `ojd record draft` builds from a descriptor and captured input reports.
struct ControllerRecordDraftTests {
  /// Report 1: eight buttons in byte 1, a hat in the low nibble of byte 2, X and Y in bytes 3
  /// and 4, and Z in byte 5.
  private static let descriptor: [UInt8] = [
    0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0x85, 0x01,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x08, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
    0x05, 0x01, 0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
    0x75, 0x04, 0x95, 0x01, 0x81, 0x03,
    0x09, 0x30, 0x09, 0x31, 0x15, 0x00, 0x26, 0xFF, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
    0x09, 0x32, 0x95, 0x01, 0x81, 0x02,
    0xC0,
  ]
  /// A model without a bundled record.
  private static let unbundled = ControllerIdentity(vendorID: 0x1234, productID: 0x5678)
  private static let reports: [[UInt8]] = [
    [1, 0, 8, 128, 128, 0], [1, 1, 8, 128, 128, 0], [1, 0, 0, 200, 128, 0],
    [2, 9, 9, 9, 9, 9], [1, 0],
  ]

  @Test
  func mapsTheControlsTheDescriptorStates() throws {
    let draft = try #require(
      ControllerRecordDraft(
        identity: Self.unbundled,
        bundled: false,
        descriptor: Self.descriptor,
        reports: Self.reports
      )
    )
    #expect(draft.operation == .add && draft.family == .hidReportLayout)
    #expect(draft.reportID == 1 && draft.reportLength == 6)
    let document = try #require(
      JSONSerialization.jsonObject(with: draft.document) as? [String: Any]
    )
    let record = try #require(document["record"] as? [String: Any])
    let input = try #require(record["input"] as? [String: Any])
    #expect(input["report"] as? [String: Int] == ["length": 6, "id": 1])
    let buttons = try #require(input["buttons"] as? [[String: Any]])
    #expect(buttons.compactMap { $0["control"] as? String }.first == "face-south")
    #expect(buttons.compactMap { $0["mask"] as? Int } == [1, 2, 4, 8, 16, 32, 64, 128])
    #expect(buttons.allSatisfy { $0["byte"] as? Int == 1 })
    let axes = try #require(input["axes"] as? [[String: Any]])
    #expect(axes.map { $0.count } == [2, 2])
    #expect(axes.compactMap { $0["byte"] as? Int } == [3, 4])
    let hat = try #require((input["hat"] as? [[String: Any]])?.first)
    #expect(hat["encoding"] as? String == "8-way" && hat["byte"] as? Int == 2)
    #expect(hat["mask"] as? Int == 15)
    #expect(input["leftTrigger"] as? [String: Int] == ["byte": 5])
    #expect(input["rightTrigger"] == nil)

    let validated = try ControllerRecordSet.validate(draft.document)
    #expect(validated.operation == .add && validated.record.family == "hid.report-layout")
  }

  /// Only reports with the chosen ID and at least the chosen length count.
  @Test
  func reportsTheBytesThatChanged() throws {
    let draft = try #require(
      ControllerRecordDraft(
        identity: Self.unbundled,
        bundled: false,
        descriptor: Self.descriptor,
        reports: Self.reports
      )
    )
    #expect(draft.capturedReports == 3)
    #expect(
      draft.changedBytes == [
        .init(byte: 1, minimum: 0, maximum: 1), .init(byte: 2, minimum: 0, maximum: 8),
        .init(byte: 3, minimum: 128, maximum: 200),
      ]
    )
  }

  @Test
  func patchesABundledModel() throws {
    let bundled = try #require(
      ControllerRecordSet.bundled.records.values.first { $0.family == "hid.descriptor" }
    )
    let draft = try #require(
      ControllerRecordDraft(
        identity: bundled.identity,
        bundled: true,
        descriptor: Self.descriptor,
        reports: []
      )
    )
    #expect(draft.operation == .patch && draft.capturedReports == 0 && draft.changedBytes.isEmpty)
    let validated = try ControllerRecordSet.validate(draft.document)
    #expect(validated.operation == .patch && validated.record.family == "hid.report-layout")
  }

  /// Without a usable descriptor, a new model gets `hid.descriptor` and the common report length.
  @Test(arguments: [nil, [0x05, 0x01, 0x09, 0x05, 0xA1, 0x01, 0xC0]] as [[UInt8]?])
  func fallsBackToTheDescriptorFamily(descriptor: [UInt8]?) throws {
    let reports: [[UInt8]] = [[0, 1, 2], [0, 1, 3], [0, 1, 2], [7]]
    let draft = try #require(
      ControllerRecordDraft(
        identity: Self.unbundled,
        bundled: false,
        descriptor: descriptor,
        reports: reports
      )
    )
    #expect(draft.operation == .add && draft.family == .hidDescriptor)
    #expect(draft.reportID == nil && draft.reportLength == 3 && draft.capturedReports == 3)
    #expect(draft.changedBytes == [.init(byte: 2, minimum: 2, maximum: 3)])
    #expect(try ControllerRecordSet.validate(draft.document).record.family == "hid.descriptor")
    #expect(
      ControllerRecordDraft(
        identity: Self.unbundled,
        bundled: true,
        descriptor: descriptor,
        reports: reports
      ) == nil
    )
  }
}
