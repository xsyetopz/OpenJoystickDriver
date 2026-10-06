import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The persisted profile JSON shape of `ControllerColor`, alone and in a physical colour output.
struct ControllerColorTests {
  func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
  }

  @Test
  func encodesFlatChannelsAndRejectsUnknownKeys() throws {
    let color = ControllerColor(red: 1, green: 2, blue: 255)
    #expect(try json(color) == #"{"blue":255,"green":2,"red":1}"#)
    #expect(
      try json(RemappingPhysicalOutput.color(color))
        == #"{"blue":255,"green":2,"red":1,"type":"color"}"#
    )
    #expect(
      try JSONDecoder().decode(
        ControllerColor.self,
        from: Data(#"{"red":1,"green":2,"blue":255}"#.utf8)
      ) == color
    )
    for invalid in [#"{"red":1,"green":2,"blue":3,"alpha":4}"#, #"{"red":256,"green":0,"blue":0}"#]
    {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ControllerColor.self, from: Data(invalid.utf8))
      }
    }
  }

  @Test
  func parsesSixHexDigitsWithAnOptionalHash() {
    #expect(ControllerColor(hex: "#FF0080") == ControllerColor(red: 255, green: 0, blue: 128))
    #expect(ControllerColor(hex: "0a0b0c") == ControllerColor(red: 10, green: 11, blue: 12))
    for invalid in ["", "#", "FFF", "#FF00800", "GG0000", "+F0000", "##FF0000"] {
      #expect(ControllerColor(hex: invalid) == nil)
    }
  }
}
