import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The control vocabulary: the Swift enum, the schema definitions, and the
/// crosswalk to SDL and the system HID names.
struct ControlVocabularyTests {
  @Test
  func anIDOutsideTheVocabularyDoesNotDecode() {
    let data = Data("\"x\(UUID().uuidString)\"".utf8)

    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(Control.self, from: data)
    }
  }

  @Test
  func everyIDIsUpperCamelCase() {
    for control in Control.allCases {
      let id = control.rawValue
      #expect(id.first?.isUppercase == true, "\(id)")
      #expect(id.allSatisfy { $0.isLetter || $0.isNumber }, "\(id)")
    }
    #expect(Set(Control.allCases.map(\.rawValue)).count == Control.allCases.count)
  }

  @Test
  func schemaDefinitionsMatchTheSwiftCases() throws {
    let definitions = try Self.vocabularyDefinitions()
    func values(_ name: String) -> [String]? {
      (definitions[name] as? [String: Any])?["enum"] as? [String]
    }
    #expect(values("control") == Control.allCases.map(\.rawValue))
    #expect(
      Set(values("dpadControl") ?? []) == Set(Control.dpad.map(\.rawValue)),
      "dpadControl"
    )
    #expect(values("stickAxis") == Control.stickAxes.map(\.rawValue))
    #expect(values("axis") == RemappingAxis.allCases.map(\.rawValue))
    #expect(values("horizontalStickAxis") == ["LeftStickX", "RightStickX"])
    #expect(values("trigger") == ["LeftTrigger", "RightTrigger"])
  }

  // MARK: Crosswalk

  private struct Crosswalk: Decodable {
    struct Row: Decodable {
      struct HID: Decodable, Hashable {
        let page: String
        let usage: Int?
      }
      let w3cButton: Int?
      let w3cAxis: Int?
      let sdl: String?
      let evdev: String?
      let hid: [HID]
      let apple: String?
      let notes: [String: String]?
    }
    struct Source: Decodable {
      let document: String
      let version: String
      let revision: String?
      let url: String
      let checkedOn: String
      let pages: [String: Int]?
    }
    let sources: [String: Source]
    let controls: [String: Row]
  }

  private static func crosswalk() throws -> Crosswalk {
    let url = JSONSchemaFiles.directory.deletingLastPathComponent()
      .appendingPathComponent("Vocabulary/crosswalk.json")
    return try JSONDecoder().decode(Crosswalk.self, from: Data(contentsOf: url))
  }

  private static func vocabularyDefinitions() throws -> [String: Any] {
    try #require(
      try JSONSchemaFiles.document(named: "vocabulary.schema.json")["$defs"] as? [String: Any]
    )
  }

  @Test
  func crosswalkHasOneRowPerControl() throws {
    let rows = try Self.crosswalk().controls
    #expect(Set(rows.keys) == Set(Control.allCases.map(\.rawValue)))
    let definitions = try Self.vocabularyDefinitions()
    let schemaIDs = (definitions["control"] as? [String: Any])?["enum"] as? [String]
    #expect(Set(rows.keys) == Set(schemaIDs ?? []))
  }

  /// Each system name leads back to the control: the reverse index of a name contains its id.
  ///
  /// Two ids may share a name (`MISC1` is Capture and Microphone), so the index holds sets.
  @Test
  func crosswalkRoundTripsEveryControl() throws {
    let rows = try Self.crosswalk().controls
    var bySDL: [String: Set<String>] = [:]
    var byEvdev: [String: Set<String>] = [:]
    var byApple: [String: Set<String>] = [:]
    var byW3CButton: [Int: Set<String>] = [:]
    var byW3CAxis: [Int: Set<String>] = [:]
    var byHID: [Crosswalk.Row.HID: Set<String>] = [:]
    for (id, row) in rows {
      if let sdl = row.sdl { bySDL[sdl, default: []].insert(id) }
      if let evdev = row.evdev { byEvdev[evdev, default: []].insert(id) }
      if let apple = row.apple { byApple[apple, default: []].insert(id) }
      if let button = row.w3cButton { byW3CButton[button, default: []].insert(id) }
      if let axis = row.w3cAxis { byW3CAxis[axis, default: []].insert(id) }
      for entry in row.hid { byHID[entry, default: []].insert(id) }
    }
    for control in Control.allCases {
      let id = control.rawValue
      let row = try #require(rows[id], "\(id)")
      #expect(row.sdl.map { bySDL[$0]?.contains(id) == true } ?? true, "\(id) sdl")
      #expect(row.evdev.map { byEvdev[$0]?.contains(id) == true } ?? true, "\(id) evdev")
      #expect(row.apple.map { byApple[$0]?.contains(id) == true } ?? true, "\(id) apple")
      #expect(row.w3cButton.map { byW3CButton[$0] == [id] } ?? true, "\(id) w3c button")
      #expect(row.w3cAxis.map { byW3CAxis[$0] == [id] } ?? true, "\(id) w3c axis")
      #expect(row.hid.allSatisfy { byHID[$0]?.contains(id) == true }, "\(id) hid")
      // Every id a name leads to is a vocabulary id.
      for ids in bySDL.values { #expect(ids.allSatisfy { Control(rawValue: $0) != nil }) }
    }
    #expect(bySDL["MISC1"] == ["Capture", "Microphone"])
  }

  @Test
  func crosswalkKeepsTheDocumentedFixedPoints() throws {
    let rows = try Self.crosswalk().controls
    #expect(rows["South"]?.sdl == "SOUTH")
    #expect(rows["South"]?.w3cButton == 0)
    #expect(rows["Back"]?.sdl == "BACK")
    #expect(rows["Back"]?.w3cButton == 8)
    #expect(rows["Guide"]?.w3cButton == 16)
    #expect(rows["LeftStickX"]?.w3cAxis == 0)
    #expect(rows["RightStickY"]?.w3cAxis == 3)
    #expect(rows["DpadRight"]?.w3cButton == 15)
    #expect(rows["South"]?.hid == [.init(page: "Button", usage: 1)])
  }

  @Test
  func crosswalkRecordsASourcePerColumn() throws {
    let crosswalk = try Self.crosswalk()
    #expect(Set(crosswalk.sources.keys) == ["w3c", "sdl", "evdev", "hid", "apple"])
    for (column, source) in crosswalk.sources {
      #expect(!source.document.isEmpty && !source.version.isEmpty, "\(column)")
      #expect(source.url.hasPrefix("https://"), "\(column)")
      #expect(!source.checkedOn.isEmpty, "\(column)")
    }
    #expect(crosswalk.sources["sdl"]?.revision?.count == 40)
    #expect(crosswalk.sources["evdev"]?.revision?.count == 40)
    let pages = Set(crosswalk.sources["hid"]?.pages?.keys.sorted() ?? [])
    for (id, row) in crosswalk.controls {
      #expect(row.hid.allSatisfy { pages.contains($0.page) }, "\(id) hid page")
      #expect((row.notes ?? [:]).keys.allSatisfy { crosswalk.sources[$0] != nil }, "\(id) note")
    }
  }

  @Test
  func crosswalkHoldsTheSourcedCells() throws {
    let rows = try Self.crosswalk().controls
    #expect(rows["LeftTrigger"]?.hid.contains(.init(page: "Simulation", usage: 197)) == true)
    #expect(rows["RightTrigger"]?.hid.contains(.init(page: "Simulation", usage: 196)) == true)
    #expect(rows["TouchpadClick"]?.evdev == "BTN_LEFT")
    #expect(rows["TouchpadClick"]?.apple == "DualShockTouchpadButton")
    #expect(rows["RightPaddle1"]?.apple == "XboxPaddleOne")
    #expect(rows["RightPaddle2"]?.apple == "XboxPaddleTwo")
    #expect(rows["LeftPaddle1"]?.apple == "XboxPaddleThree")
    #expect(rows["LeftPaddle2"]?.apple == "XboxPaddleFour")
    #expect(rows["DpadUp"]?.hid.first == .init(page: "GenericDesktop", usage: 144))
    #expect(rows["Capture"]?.hid == [.init(page: "Consumer", usage: 178)])
    for id in [
      "LeftStickTouch", "LeftTrackpadClick", "RightTrackpadTouch", "LeftGripTouch",
      "RightGripTouch",
    ] {
      let row = try #require(rows[id])
      #expect(row.hid.isEmpty && row.sdl == nil && row.evdev == nil && row.apple == nil, "\(id)")
    }
  }

  private static func crosswalkText(
    editing edit: (inout [String: Any]) -> Void = { _ in }
  ) throws
    -> String
  {
    let url = JSONSchemaFiles.directory.deletingLastPathComponent()
      .appendingPathComponent("Vocabulary/crosswalk.json")
    var document = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    )
    edit(&document)
    let data = try JSONSerialization.data(withJSONObject: document)
    return try #require(String(bytes: data, encoding: .utf8))
  }

  @Test
  func crosswalkMatchesItsSchema() throws {
    let issues = try JSONSchemaFiles.issues(
      in: Self.crosswalkText(),
      against: "crosswalk.schema.json#"
    )
    #expect(issues.isEmpty, "\(issues)")
  }

  @Test
  func crosswalkSchemaRejectsAPlantedBadFile() throws {
    func rejects(_ name: String, _ edit: @escaping (inout [String: Any]) -> Void) throws {
      let issues = try JSONSchemaFiles.issues(
        in: Self.crosswalkText(editing: edit),
        against: "crosswalk.schema.json#"
      )
      #expect(!issues.isEmpty, "\(name)")
    }
    func change(
      _ document: inout [String: Any],
      _ key: String,
      _ edit: (inout [String: Any]) -> Void
    ) {
      var section = document[key] as? [String: Any] ?? [:]
      edit(&section)
      document[key] = section
    }
    try rejects("unknown top-level member") { $0["extra"] = true }
    try rejects("wrong kind") { $0["kind"] = "Other" }
    try rejects("missing source column") { change(&$0, "sources") { $0["apple"] = nil } }
    try rejects("source without a date") {
      change(&$0, "sources") { sources in
        var sdl = sources["sdl"] as? [String: Any] ?? [:]
        sdl["checkedOn"] = nil
        sources["sdl"] = sdl
      }
    }
    try rejects("unknown control id") {
      change(&$0, "controls") { $0["Cross"] = $0["South"] }
    }
    try rejects("row with an unknown column") {
      change(&$0, "controls") { controls in
        var row = controls["South"] as? [String: Any] ?? [:]
        row["gcc"] = "ButtonA"
        controls["South"] = row
      }
    }
    try rejects("row without a column") {
      change(&$0, "controls") { controls in
        var row = controls["South"] as? [String: Any] ?? [:]
        row["evdev"] = nil
        controls["South"] = row
      }
    }
  }
}
