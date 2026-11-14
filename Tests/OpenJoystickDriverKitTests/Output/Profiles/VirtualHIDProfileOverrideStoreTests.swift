import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileOverrideStoreTests {
  private typealias Store = VirtualHIDProfileOverrideStore

  private static let unit = "U-AbCd_123-xyzW09q"

  private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = MacOSDataDirectory().url(for: .temporary)
      .appendingPathComponent("PersonaStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private func write(_ json: String, named name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try PropertyListFixture.bytes(json: json).write(to: directory.appendingPathComponent(name))
  }

  private func persona(
    vendorID: Int,
    productID: Int,
    unit: String? = nil,
    descriptor: String = "Generic",
    identity: String? = nil
  ) -> String {
    let match =
      #"{"vendorID":\#(vendorID),"productID":\#(productID)"#
      + (unit.map { #","unit":"\#($0)""# } ?? "") + "}"
    return
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(Store.kind)","#
      + #""match":\#(match),"persona":"\#(descriptor)""#
      + (identity.map { #","identity":\#($0)"# } ?? "") + "}"
  }

  private static let identityJSON =
    #"{"vendorID":4660,"productID":22136,"productName":"Arcade Stick","#
    + #""manufacturer":"Acme"}"#

  @Test
  func personaSelectionWithoutMatchIsInvalidControllerRecord() {
    let document =
      #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(Store.kind)","#
      + #""persona":"Generic"}"#
    let problem = #expect(throws: ControllerRecordProblem.self) {
      try Store.parse(PropertyListFixture.bytes(json: document))
    }
    #expect(problem?.description == "the file must hold match")
    #expect(problem?.code == .invalidControllerRecord)
    #expect(problem.flatMap { ControllerRecordSet.problemCode($0) } == .invalidControllerRecord)
  }

  @Test
  func absentDirectoryHasNoPersonas() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.loadError == nil)
      #expect(store.files.isEmpty)
    }
  }

  @Test
  func overrideRoundTripsThroughPersonaFile() throws {
    try withDirectory { directory in
      try Store(directory: directory).set(.generic, vendorID: 0x045E, productID: 0x02EA)

      #expect(Store(directory: directory).override(vendorID: 0x045E, productID: 0x02EA) == .generic)
      let url = directory.appendingPathComponent("045e-02ea.plist")
      let document = try PropertyListFixture.dictionary(at: url)
      #expect(document["$schema"] == nil)
      #expect(document["apiVersion"] as? String == OpenJoystickDriverAPI.version)
      #expect(document["kind"] as? String == Store.kind)
      #expect(document["persona"] as? String == "Generic")
      let match = try #require(document["match"] as? [String: Any])
      #expect(match["vendorID"] as? Int == 0x045E)
      #expect(match["productID"] as? Int == 0x02EA)
      #expect(match["unit"] == nil)
    }
  }

  @Test
  func overridesAreIsolatedPerControllerModel() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      try store.set(.generic, vendorID: 0x045E, productID: 0x02EA)
      try store.set(.sdlCompatible, vendorID: 0x054C, productID: 0x0CE6)

      try store.reset(vendorID: 0x045E, productID: 0x02EA)

      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.override(vendorID: 0x054C, productID: 0x0CE6) == .sdlCompatible)
      #expect(store.override(vendorID: 0x054C, productID: 0x02EA) == nil)
    }
  }

  @Test
  func unitPersonaBeatsItsModelAndResettingItFallsBack() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      try store.set(.generic, vendorID: 1, productID: 2)
      try store.set(.sdlCompatible, vendorID: 1, productID: 2, unit: Self.unit)

      #expect(
        store.override(vendorID: 1, productID: 2, unit: Self.unit) == .sdlCompatible
      )
      #expect(store.override(vendorID: 1, productID: 2, unit: "U-0000000000000000") == .generic)
      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.storedOverride(vendorID: 1, productID: 2, unit: "U-0000000000000000") == nil)

      try store.reset(vendorID: 1, productID: 2, unit: Self.unit)
      #expect(store.override(vendorID: 1, productID: 2, unit: Self.unit) == .generic)
    }
  }

  @Test
  func fileThatIsNotPersonaIsSkippedAndRestApply() throws {
    try withDirectory { directory in
      try write(persona(vendorID: 1, productID: 2), named: "a.plist", in: directory)
      try write(#"{"match":{}}"#, named: "b.plist", in: directory)
      try write(
        persona(vendorID: 3, productID: 4, descriptor: "xbox-360"),
        named: "c.plist",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.loadError == nil)
      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.override(vendorID: 3, productID: 4) == nil)
      #expect(store.problems.map(\.url.lastPathComponent) == ["b.plist", "c.plist"])
      #expect(store.files.first?.problem == nil)
    }
  }

  @Test
  func staleJSONPersonaIsListedAsStale() throws {
    try withDirectory { directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try Data("{}".utf8).write(to: directory.appendingPathComponent("045e-02ea.json"))
      let store = Store(directory: directory)

      #expect(store.problems.map(\.url.lastPathComponent) == ["045e-02ea.json"])
      #expect(store.problems.first?.problem == DocumentMigrator.staleProblem)
    }
  }

  @Test
  func fileWithUnsupportedAPIVersionIsSkipped() throws {
    try withDirectory { directory in
      let unsupported = persona(vendorID: 1, productID: 2).replacingOccurrences(
        of: OpenJoystickDriverAPI.version,
        with: "unsupported.example/v9"
      )
      try write(unsupported, named: "unsupported.plist", in: directory)
      let store = Store(directory: directory)

      #expect(store.override(vendorID: 1, productID: 2) == nil)
      #expect(store.problems.first?.problem?.hasPrefix("E5001: ") == true)
      #expect(
        store.problems.first?.problem?.contains(
          "apiVersion unsupported.example/v9 is not supported"
        ) == true
      )
      #expect(store.problems.first?.problem?.contains(OpenJoystickDriverAPI.version) == true)
    }
  }

  @Test
  func fileWithoutAPIVersionIsSkippedWithE5001() throws {
    try withDirectory { directory in
      let missing = persona(vendorID: 1, productID: 2).replacingOccurrences(
        of: #""apiVersion":"\#(OpenJoystickDriverAPI.version)","#,
        with: ""
      )
      try write(missing, named: "missing.plist", in: directory)
      let store = Store(directory: directory)

      #expect(store.override(vendorID: 1, productID: 2) == nil)
      #expect(store.problems.first?.problem?.hasPrefix("E5001: ") == true)
      #expect(store.problems.first?.problem?.contains("no apiVersion found") == true)
    }
  }

  @Test
  func secondFileWithSameMatchIsSkipped() throws {
    try withDirectory { directory in
      try write(persona(vendorID: 1, productID: 2), named: "a.plist", in: directory)
      try write(
        persona(vendorID: 1, productID: 2, descriptor: "SDLCompatible"),
        named: "b.plist",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.problems.map(\.url.lastPathComponent) == ["b.plist"])
      #expect(store.problems.first?.problem?.contains("a.plist") == true)
    }
  }

  @Test
  func personaDefinesIdentityOverBuiltInDescriptor() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.plist",
        in: directory
      )
      let found = try #require(Store(directory: directory).persona(vendorID: 1, productID: 2))

      #expect(found.descriptor == .generic)
      #expect(found.identity?.vendorID == 4660)
      #expect(found.identity?.productID == 22136)
      #expect(found.identity?.productName == "Arcade Stick")
      #expect(found.identity?.manufacturer == "Acme")
      #expect(found.identity?.glyphFamily == .generic)
    }
  }

  @Test
  func incompleteIdentityMakesFileInvalid() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: #"{"vendorID":4660,"productID":1}"#),
        named: "stick.plist",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.persona(vendorID: 1, productID: 2) == nil)
      #expect(store.problems.count == 1)
    }
  }

  @Test
  func resetAllKeepsPersonasWithIdentityAndFilesItSkipped() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      try store.set(.generic, vendorID: 5, productID: 6)
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.plist",
        in: directory
      )
      try write("not json", named: "broken.plist", in: directory)

      let kept = try store.resetAll()

      #expect(
        kept == [directory.appendingPathComponent("stick.plist").realPath]
      )
      #expect(store.override(vendorID: 5, productID: 6) == nil)
      #expect(store.persona(vendorID: 1, productID: 2)?.identity != nil)
      #expect(store.files.map(\.url.lastPathComponent) == ["broken.plist", "stick.plist"])
    }
  }

  @Test
  func resettingPersonaWithIdentityFailsAndKeepsFile() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.plist",
        in: directory
      )
      let store = Store(directory: directory)
      let path = directory.appendingPathComponent("stick.plist").realPath

      #expect(throws: VirtualHIDProfileOverrideError.keptFile(path)) {
        try store.reset(vendorID: 1, productID: 2)
      }
      #expect(store.persona(vendorID: 1, productID: 2)?.identity != nil)
    }
  }

  @Test
  func settingOverrideKeepsIdentityOfMatchingPersona() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.plist",
        in: directory
      )
      let store = Store(directory: directory)

      try store.set(.sdlCompatible, vendorID: 1, productID: 2)

      let found = try #require(store.persona(vendorID: 1, productID: 2))
      #expect(found.descriptor == .sdlCompatible)
      #expect(found.identity?.productName == "Arcade Stick")
      #expect(store.files.map(\.url.lastPathComponent) == ["stick.plist"])
    }
  }

  @Test
  func unreadableDirectoryIsErrorAndWritesFail() throws {
    try withDirectory { directory in
      try Data().write(to: directory)
      let store = Store(directory: directory)

      #expect(store.loadError != nil)
      #expect(store.override(vendorID: 1, productID: 2) == nil)
      #expect(throws: VirtualHIDProfileOverrideError.self) {
        try store.set(.generic, vendorID: 1, productID: 2)
      }
    }
  }
}
