import Testing

@testable import OpenJoystickDriverKit

struct InputMappingTextTests {
  private static let formats = [
    "cli.controller.show.inputMappingRecord": "record",
    "cli.controller.show.inputMappingSDL": "sdl %1$@ %2$@",
    "cli.controller.show.inputMappingStandard": "standard",
    "cli.controller.show.inputMappingRejected": "rejected %@",
    "cli.controller.show.inputMappingUnbound": "unbound %1$@ %2$@",
  ]

  private func text(_ mapping: InputMapping) -> String {
    mapping.rowText { Self.formats[$0] ?? $0 }
  }

  @Test
  func eachSourceHasItsRowText() {
    let guid = "03000000c82d00000160000000000000"
    func mapping(_ source: InputMapping.Source, rejection: String? = nil) -> InputMapping {
      InputMapping(
        source: source,
        guid: guid,
        match: .guidWithoutNameCRC,
        unmapped: [],
        rejection: rejection
      )
    }
    #expect(text(.record) == "record")
    #expect(text(mapping(.sdlGameControllerDB)) == "sdl GUIDWithoutNameCRC \(guid)")
    #expect(text(.standardHIDUsageMap) == "standard")
    #expect(text(mapping(.standardHIDUsageMap, rejection: "b9 past 8")) == "rejected b9 past 8")
    #expect(text(mapping(.none)) == "unbound GUIDWithoutNameCRC \(guid)")
  }
}
