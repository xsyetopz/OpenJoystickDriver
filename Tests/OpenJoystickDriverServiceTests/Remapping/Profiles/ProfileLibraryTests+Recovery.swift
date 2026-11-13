import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

extension ProfileLibraryTests {
  @Test
  func jsonProfileOfEarlierAlphaNamedWithE5001() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      try await library.create(valid)
      let stale = library.profilesDirectory.appendingPathComponent("OLD.json")
      try Data(#"{"apiVersion": "openjoystickdriver/v1alpha1", "kind": "Profile"}"#.utf8)
        .write(to: stale)
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.code) == [.unsupportedAPIVersion])
      #expect(snapshot.issues.first?.fileName == "OLD.json")
      #expect(snapshot.issues.first?.message.contains("OLD.json") == true)
      #expect(FileManager.default.fileExists(atPath: stale.path))
    }
  }

  @Test
  func jsonFileOJDDidNotWriteLeftOutOfIssues() async throws {
    try await withLibrary { library, _ in
      try await library.create(makeProfile(name: "Valid"))
      let notes = library.profilesDirectory.appendingPathComponent("notes.json")
      try Data(#"{"apiVersion": "example.org/v1", "kind": "Profile"}"#.utf8).write(to: notes)
      let text = library.profilesDirectory.appendingPathComponent("todo.json")
      try Data("not json".utf8).write(to: text)
      _ = try await library.reload()

      #expect(try await library.snapshot().issues.isEmpty)
    }
  }

  @Test
  func profileWithUnknownFieldIsRecoveredAsDamaged() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Unknown")
      try await library.create(valid)
      var storedObject = try #require(
        PropertyListFixture.tree(Data(RemappingProfileFileStore.encodedPlist(stored).utf8))
          as? [String: Any]
      )
      storedObject["notAField"] = true
      try PropertyListFixture.data(tree: storedObject)
        .write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
    }
  }

  /// A stored profile that names a control the vocabulary does not have is damaged like any
  /// other: dropped from the snapshot, reported, its bytes left as they were.
  @Test(arguments: ["NotAControl", "a", ""])
  func profileWithUnknownControlNameIsRecoveredAsDamaged(name: String) async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      var object = try #require(
        PropertyListFixture.tree(Data(RemappingProfileFileStore.encodedPlist(stored).utf8))
          as? [String: Any]
      )
      object["bindings"] = [
        [
          "id": UUID().uuidString,
          "source": ["type": "Button", "button": name],
          "destination": ["type": "Keyboard", "key": "Space", "modifiers": [String]()],
        ] as [String: Any]
      ]
      let bytes = try PropertyListFixture.data(tree: object)
      try bytes.write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid])
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile])
      #expect(try Data(contentsOf: library.profileURL(stored.id)) == bytes)
    }
  }

  /// Each profile file the library cannot use is reported with the code a request gives the same
  /// failure.
  @Test
  func damagedProfileIssuesCarryTheCodeOfTheirSituation() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      try await library.create(valid)
      let invalidHeader = PropertyListFixture.bytes(
        json: #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Profile","name":"Pad"}"#
      )
      let unsupported = PropertyListFixture.bytes(
        json: #"{"apiVersion":"unsupported.example/v9","kind":"Profile"}"#
      )
      let misnamed = makeProfile(name: "Misnamed")
      let duplicate = makeProfile(name: "valid")
      try invalidHeader.write(to: library.profileURL(UUID()))
      try unsupported.write(to: library.profileURL(UUID()))
      try Data(RemappingProfileFileStore.encodedPlist(misnamed).utf8)
        .write(to: library.profileURL(UUID()))
      try Data(RemappingProfileFileStore.encodedPlist(duplicate).utf8)
        .write(to: library.profileURL(duplicate.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.issues.allSatisfy { $0.kind == .damagedProfile })
      let codes = Set(snapshot.issues.map(\.code))
      let expected: Set<ErrorCode> = [
        .corruptLibrary, .duplicateName, .invalidProfile, .unsupportedAPIVersion,
      ]
      #expect(codes == expected)
      #expect(snapshot.issues.count == 4)
    }
  }

  @Test
  func profileWithCurrentControlNameLoads() async throws {
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      var object = try #require(
        PropertyListFixture.tree(Data(RemappingProfileFileStore.encodedPlist(stored).utf8))
          as? [String: Any]
      )
      object["bindings"] = [
        [
          "id": UUID().uuidString,
          "source": ["type": "Button", "button": "South"],
          "destination": ["type": "Keyboard", "key": "Space", "modifiers": [String]()],
        ] as [String: Any]
      ]
      try PropertyListFixture.data(tree: object).write(to: library.profileURL(stored.id))
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(Set(snapshot.profiles.map(\.id)) == [valid.id, stored.id])
      #expect(snapshot.issues.isEmpty)
    }
  }

  private static let bindingID = "6F1C2D3E-4A5B-4C6D-8E7F-901A2B3C4D61"

  /// A binding with one source and one destination, as JSON.
  private static func binding(
    source: String = #"{"type":"Button","button":"South"}"#,
    destination: String = #"{"type":"Keyboard","key":"Space","modifiers":[]}"#,
    extra: String = ""
  ) -> String {
    #"{"outputPolicy":{"virtualGamepad":"Mapped","physicalInput":"Exclusive"},"#
      + #""bindings":[{"id":"\#(bindingID)","source":\#(source),"#
      + #""destination":\#(destination)\#(extra)}]}"#
  }

  /// Profile members written in the current spelling, with the spelling they replace.
  private static let renamedKinds: [(document: String, current: String, replaced: String)] = [
    (#"{"applicationScope":{"type":"Global"}}"#, #""Global""#, #""global""#),
    (
      #"{"outputPolicy":{"virtualGamepad":"Passthrough","physicalInput":"Exclusive"}}"#,
      #""Passthrough""#, #""passthrough""#
    ),
    (
      #"{"outputPolicy":{"virtualGamepad":"Disabled","physicalInput":"Exclusive"}}"#,
      #""Exclusive""#, #""exclusive""#
    ),
    (binding(extra: #","behavior":"TapOnPress""#), #""TapOnPress""#, #""tap_on_press""#),
    (
      binding(
        source: #"{"type":"Axis","axis":"LeftStickX"}"#,
        destination: #"{"type":"GamepadAxis","axis":"RightStickX"}"#,
        extra: #","axisTuning":{"deadzone":0.1,"gain":1,"inverted":false,"#
          + #""responseCurve":"EaseIn","digitalActivationThreshold":0.5}"#
      ), #""EaseIn""#, #""ease_in""#
    ),
    (
      binding(destination: #"{"type":"MouseButton","button":"Left"}"#), #""MouseButton""#,
      #""mouse_button""#
    ),
    (binding(destination: #"{"type":"MouseButton","button":"Left"}"#), #""Left""#, #""left""#),
    (
      binding(
        source: #"{"type":"AxisDirection","axis":"LeftStickX","direction":"Negative"}"#,
        extra: #","axisTuning":{"deadzone":0.2,"gain":1,"inverted":false,"#
          + #""responseCurve":"Linear","digitalActivationThreshold":0.6}"#
      ),
      #""AxisDirection""#, #""axis_direction""#
    ),
    (
      binding(
        destination: #"{"type":"Physical","physical":{"type":"Rumble","motor":"LowFrequency","#
          + #""intensity":0.5}}"#
      ), #""LowFrequency""#, #""leftMain""#
    ),
    (
      binding(
        destination: #"{"type":"Physical","physical":{"type":"AdaptiveTrigger","trigger":"Left","#
          + #""effect":{"kind":"Resistance","startPosition":0.2,"strength":0.5}}}"#
      ), #""Resistance""#, #""resistance""#
    ),
    (
      #"{"triggerMappings":[{"source":"Left","mode":"PreferFull"}]}"#, #""PreferFull""#,
      #""prefer_full""#
    ),
    (#"{"triggerMappings":[{"source":"Left","mode":"Exclusive"}]}"#, #""Left""#, #""left""#),
    (
      #"{"chords":[{"id":"\#(bindingID)","sources":["#
        + #"{"type":"Button","button":"South"},{"type":"Button","button":"East"}],"#
        + #""destination":{"type":"Keyboard","key":"Space","modifiers":[]},"mode":"Modifier"}]}"#,
      #""Modifier""#, #""modifier""#
    ),
    (
      #"{"layers":[{"id":"\#(bindingID)","name":"Layer","activationMode":"Toggle","#
        + #""activator":{"type":"Button","button":"North"},"bindings":[],"#
        + #""chords":[],"sequences":[]}]}"#,
      #""Toggle""#,
      #""toggle""#
    ),
    (#"{"stickMappings":[{"source":"Left","mode":"Aim"}]}"#, #""Left""#, #""left""#),
    (#"{"motionTuning":{"space":"World"}}"#, #""World""#, #""world""#),
    (
      #"{"touchMappings":[{"id":"\#(bindingID)","surface":"Primary","mode":"Pointer","#
        + #""deadzone":0.1,"pointerSensitivity":100,"stickRadius":0.5}]}"#,
      #""Primary""#, #""primary""#
    ),
  ]

  /// Merges `document`, a JSON object of profile members, into a stored profile file.
  private func store(
    _ document: String,
    replacing replaced: String? = nil,
    with current: String? = nil,
    in library: RemappingProfileLibrary,
    as stored: RemappingProfile
  ) throws -> Data {
    var object = try #require(
      PropertyListFixture.tree(Data(RemappingProfileFileStore.encodedPlist(stored).utf8))
        as? [String: Any]
    )
    var text = document
    if let replaced, let current { text = text.replacingOccurrences(of: current, with: replaced) }
    let members = try #require(
      JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    )
    object.merge(members) { _, member in member }
    let bytes = try PropertyListFixture.data(tree: object)
    try bytes.write(to: library.profileURL(stored.id))
    return bytes
  }

  /// A stored profile that spells a kind in the way before the UpperCamelCase rule is damaged with
  /// the invalid-profile code, and its bytes stay as they were.
  @Test(arguments: 0..<17)
  func profileWithAnUnknownKindSpellingIsRecoveredAsDamaged(index: Int) async throws {
    let kind = Self.renamedKinds[index]
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      let bytes = try store(
        kind.document,
        replacing: kind.replaced,
        with: kind.current,
        in: library,
        as: stored
      )
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.profiles == [valid], "\(kind.replaced)")
      #expect(snapshot.issues.map(\.kind) == [.damagedProfile], "\(kind.replaced)")
      #expect(snapshot.issues.map(\.code) == [.invalidProfile], "\(kind.replaced)")
      #expect(try Data(contentsOf: library.profileURL(stored.id)) == bytes)
    }
  }

  @Test(arguments: 0..<17)
  func profileWithTheCurrentKindSpellingLoads(index: Int) async throws {
    let kind = Self.renamedKinds[index]
    try await withLibrary { library, _ in
      let valid = makeProfile(name: "Valid")
      let stored = makeProfile(name: "Stored")
      try await library.create(valid)
      _ = try store(kind.document, in: library, as: stored)
      _ = try await library.reload()

      let snapshot = try await library.snapshot()

      #expect(snapshot.issues.isEmpty, "\(kind.current) \(snapshot.issues)")
      #expect(Set(snapshot.profiles.map(\.id)) == [valid.id, stored.id], "\(kind.current)")
    }
  }
}
