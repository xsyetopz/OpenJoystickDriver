import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// An `axes` entry of a report with no ID, long enough for the field.
private func axisLayout(_ field: String, length: Int = 8) -> String {
  #"{"report": {"length": {"atLeast": \#(length)}}, "#
    + #""axes": [{"control": "LeftStickX", \#(field)}]}"#
}

struct BitFieldRawCase: CustomTestStringConvertible, Sendable {
  let name: String
  let field: String
  let bytes: [UInt8]
  let raw: Int

  var testDescription: String { name }
}

private let rawCases: [BitFieldRawCase] = [
  BitFieldRawCase(
    name: "12 bits across a byte",
    field: #""bitOffset": 4, "bitSize": 12"#,
    bytes: [0xA0, 0xBC, 0x00],
    raw: 0xBCA
  ),
  BitFieldRawCase(
    name: "10 bits from an unaligned offset",
    field: #""bitOffset": 3, "bitSize": 10"#,
    bytes: [0xF8, 0xFF, 0x00],
    raw: 0x3FF
  ),
  BitFieldRawCase(
    name: "10 bits leave the neighbors out",
    field: #""bitOffset": 3, "bitSize": 10"#,
    bytes: [0x07, 0x00, 0xF8],
    raw: 0
  ),
  BitFieldRawCase(
    name: "32 bits",
    field: #""bitOffset": 0, "bitSize": 32"#,
    bytes: [0xFF, 0xFF, 0xFF, 0xFF],
    raw: 4_294_967_295
  ),
  BitFieldRawCase(
    name: "LittleEndian is the default",
    field: #""bitOffset": 0, "bitSize": 16"#,
    bytes: [0x34, 0x12],
    raw: 0x1234
  ),
  BitFieldRawCase(
    name: "LittleEndian named",
    field: #""bitOffset": 0, "bitSize": 16, "byteOrder": "LittleEndian""#,
    bytes: [0x34, 0x12],
    raw: 0x1234
  ),
  BitFieldRawCase(
    name: "BigEndian 16",
    field: #""bitOffset": 8, "bitSize": 16, "byteOrder": "BigEndian""#,
    bytes: [0x00, 0x12, 0x34],
    raw: 0x1234
  ),
  BitFieldRawCase(
    name: "BigEndian 24",
    field: #""bitOffset": 0, "bitSize": 24, "byteOrder": "BigEndian""#,
    bytes: [0x12, 0x34, 0x56],
    raw: 0x123456
  ),
  BitFieldRawCase(
    name: "BigEndian 32",
    field: #""bitOffset": 0, "bitSize": 32, "byteOrder": "BigEndian""#,
    bytes: [0x12, 0x34, 0x56, 0x78],
    raw: 0x1234_5678
  ),
  BitFieldRawCase(
    name: "signed 12 bits, -1",
    field: #""bitOffset": 4, "bitSize": 12, "signed": true"#,
    bytes: [0xF0, 0xFF, 0x00],
    raw: -1
  ),
  BitFieldRawCase(
    name: "signed 12 bits, lowest",
    field: #""bitOffset": 4, "bitSize": 12, "signed": true"#,
    bytes: [0x00, 0x80, 0x00],
    raw: -2048
  ),
  BitFieldRawCase(
    name: "signed 12 bits, highest",
    field: #""bitOffset": 4, "bitSize": 12, "signed": true"#,
    bytes: [0xF0, 0x7F, 0x00],
    raw: 2047
  ),
  BitFieldRawCase(
    name: "signed 32 bits",
    field: #""bitOffset": 0, "bitSize": 32, "signed": true"#,
    bytes: [0x00, 0x00, 0x00, 0x80],
    raw: -2_147_483_648
  ),
  BitFieldRawCase(
    name: "signed BigEndian 16",
    field: #""bitOffset": 0, "bitSize": 16, "signed": true, "byteOrder": "BigEndian""#,
    bytes: [0xFF, 0xFE],
    raw: -2
  ),
]

/// Fields the layout rejects, with the report length they sit in.
private let rejectedFields: [(String, String)] = [
  ("zero bits", #""bitOffset": 0, "bitSize": 0"#),
  ("33 bits", #""bitOffset": 0, "bitSize": 33"#),
  ("past the report length", #""bitOffset": 57, "bitSize": 8"#),
  ("negative offset", #""bitOffset": -1, "bitSize": 8"#),
  ("unaligned BigEndian", #""bitOffset": 4, "bitSize": 16, "byteOrder": "BigEndian""#),
  ("BigEndian of 8 bits", #""bitOffset": 0, "bitSize": 8, "byteOrder": "BigEndian""#),
  ("BigEndian of 12 bits", #""bitOffset": 0, "bitSize": 12, "byteOrder": "BigEndian""#),
  ("unknown byte order", #""bitOffset": 0, "bitSize": 16, "byteOrder": "Little""#),
  ("the removed byte key", #""byte": 0"#),
  ("the removed mask key", #""bitOffset": 0, "bitSize": 8, "mask": 255"#),
  ("the removed bits key", #""byte": 0, "bits": 16"#),
  ("max beyond the size", #""bitOffset": 0, "bitSize": 8, "max": 256"#),
]

@Suite
struct BitAddressedFieldTests {
  @Test(arguments: rawCases)
  func readsTheRawValue(_ rawCase: BitFieldRawCase) throws {
    let layout = try inputLayout(axisLayout(rawCase.field, length: rawCase.bytes.count))
    #expect(layout.axes[0].field.raw(in: rawCase.bytes) == rawCase.raw)
  }

  @Test
  func aSixteenBitTriggerReadsAtAnUnalignedOffset() throws {
    let layout = try inputLayout(
      #"{"report": {"length": {"atLeast": 4}}, "#
        + #""leftTrigger": {"bitOffset": 12, "bitSize": 16}}"#
    )
    let trigger = try #require(layout.leftTrigger)
    #expect(trigger.value(in: [0x00, 0xF0, 0xFF, 0x0F]) == UnipolarValue(normalized: 1))
    #expect(trigger.value(in: [0x0F, 0x00, 0x00, 0xF0]) == UnipolarValue(normalized: 0))
  }

  @Test
  func aTwelveBitAxisScalesAroundItsMiddle() throws {
    let layout = try inputLayout(axisLayout(#""bitOffset": 4, "bitSize": 12"#, length: 3))
    let axis = layout.axes[0]
    #expect(axis.value(in: [0x00, 0x00, 0x00]) == -1)
    #expect(axis.value(in: [0x00, 0x80, 0x00]) == 0)
    #expect(axis.value(in: [0xF0, 0xFF, 0x00]) == 1)
  }

  @Test(arguments: rejectedFields)
  func rejectsInvalidFields(_ name: String, field: String) {
    #expect(throws: DecodingError.self, Comment(rawValue: name)) {
      try inputLayout(axisLayout(field))
    }
  }

  @Test
  func aFieldMayNotCoverTheReportIDByte() {
    let inID = #"{"report": {"id": 1, "length": {"atLeast": 3}}, "#
    #expect(throws: DecodingError.self) {
      try inputLayout(inID + #""axes": [{"control": "LeftStickX", "bitOffset": 7, "bitSize": 8}]}"#)
    }
    #expect(throws: DecodingError.self) {
      try inputLayout(
        inID + #""buttons": [{"control": "South", "bitOffset": 0, "bitSize": 1}]}"#
      )
    }
    #expect(throws: Never.self) {
      try inputLayout(inID + #""axes": [{"control": "LeftStickX", "bitOffset": 8, "bitSize": 8}]}"#)
    }
  }
}
