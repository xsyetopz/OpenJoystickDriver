import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProfileOverrideStoreTests {
  private typealias Store = VirtualHIDProfileOverrideStore

  private static let unit = "U-AbCd_123-xyzW09q"

  private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("PersonaStoreTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private func write(_ json: String, named name: String, in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(json.utf8).write(to: directory.appendingPathComponent(name))
  }

  private func persona(
    vendorID: Int,
    productID: Int,
    unit: String? = nil,
    descriptor: String = "hid-generic",
    identity: String? = nil
  ) -> String {
    let match =
      #"{"vendorID":\#(vendorID),"productID":\#(productID)"#
      + (unit.map { #","unit":"\#($0)""# } ?? "") + "}"
    return #"{"$schema":"\#(Store.schemaID)","match":\#(match),"descriptor":"\#(descriptor)""#
      + (identity.map { #","identity":\#($0)"# } ?? "") + "}"
  }

  private static let identityJSON =
    #"{"vendorID":4660,"productID":22136,"productName":"Arcade Stick","#
    + #""manufacturer":"Acme","glyphFamily":"generic"}"#

  @Test
  func anAbsentDirectoryHasNoPersonas() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.loadError == nil)
      #expect(store.files.isEmpty)
    }
  }

  @Test
  func anOverrideRoundTripsThroughAPersonaFile() throws {
    try withDirectory { directory in
      try Store(directory: directory).set(.generic, vendorID: 0x045E, productID: 0x02EA)

      #expect(Store(directory: directory).override(vendorID: 0x045E, productID: 0x02EA) == .generic)
      let url = directory.appendingPathComponent("045e-02ea.json")
      let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
      let document = try #require(object as? [String: Any])
      #expect(document["$schema"] as? String == Store.schemaID)
      #expect(document["descriptor"] as? String == "hid-generic")
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
      try store.set(.xboxOneSBluetooth, vendorID: 0x054C, productID: 0x0CE6)

      try store.reset(vendorID: 0x045E, productID: 0x02EA)

      #expect(store.override(vendorID: 0x045E, productID: 0x02EA) == nil)
      #expect(store.override(vendorID: 0x054C, productID: 0x0CE6) == .xboxOneSBluetooth)
      #expect(store.override(vendorID: 0x054C, productID: 0x02EA) == nil)
    }
  }

  @Test
  func aUnitPersonaBeatsItsModelAndResettingItFallsBack() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      try store.set(.generic, vendorID: 1, productID: 2)
      try store.set(.xboxOneSBluetooth, vendorID: 1, productID: 2, unit: Self.unit)

      #expect(
        store.override(vendorID: 1, productID: 2, unit: Self.unit) == .xboxOneSBluetooth
      )
      #expect(store.override(vendorID: 1, productID: 2, unit: "U-0000000000000000") == .generic)
      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.storedOverride(vendorID: 1, productID: 2, unit: "U-0000000000000000") == nil)

      try store.reset(vendorID: 1, productID: 2, unit: Self.unit)
      #expect(store.override(vendorID: 1, productID: 2, unit: Self.unit) == .generic)
    }
  }

  @Test
  func aFileThatIsNotAPersonaIsSkippedAndTheRestApply() throws {
    try withDirectory { directory in
      try write(persona(vendorID: 1, productID: 2), named: "a.json", in: directory)
      try write(#"{"match":{}}"#, named: "b.json", in: directory)
      try write(
        persona(vendorID: 3, productID: 4, descriptor: "xbox-360"),
        named: "c.json",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.loadError == nil)
      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.override(vendorID: 3, productID: 4) == nil)
      #expect(store.problems.map(\.url.lastPathComponent) == ["b.json", "c.json"])
      #expect(store.files.first?.problem == nil)
    }
  }

  @Test
  func aFileWithTheUnversionedSchemaIsSkipped() throws {
    try withDirectory { directory in
      let unversioned = persona(vendorID: 1, productID: 2).replacingOccurrences(
        of: "Schemas/v1beta1/",
        with: "Schemas/"
      )
      try write(unversioned, named: "old.json", in: directory)
      let store = Store(directory: directory)

      #expect(store.override(vendorID: 1, productID: 2) == nil)
      #expect(store.problems.first?.problem?.contains("$schema must be one of") == true)
    }
  }

  @Test
  func theSecondFileWithTheSameMatchIsSkipped() throws {
    try withDirectory { directory in
      try write(persona(vendorID: 1, productID: 2), named: "a.json", in: directory)
      try write(
        persona(vendorID: 1, productID: 2, descriptor: "hid-xbox-one-s-bt"),
        named: "b.json",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.override(vendorID: 1, productID: 2) == .generic)
      #expect(store.problems.map(\.url.lastPathComponent) == ["b.json"])
      #expect(store.problems.first?.problem?.contains("a.json") == true)
    }
  }

  @Test
  func aPersonaDefinesAnIdentityOverABuiltInDescriptor() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.json",
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
  func anIncompleteIdentityMakesTheFileInvalid() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: #"{"vendorID":4660,"productID":1}"#),
        named: "stick.json",
        in: directory
      )
      let store = Store(directory: directory)

      #expect(store.persona(vendorID: 1, productID: 2) == nil)
      #expect(store.problems.count == 1)
    }
  }

  @Test
  func resetAllKeepsPersonasWithAnIdentityAndFilesItSkipped() throws {
    try withDirectory { directory in
      let store = Store(directory: directory)
      try store.set(.generic, vendorID: 5, productID: 6)
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.json",
        in: directory
      )
      try write("not json", named: "broken.json", in: directory)

      store.resetAll()

      #expect(store.override(vendorID: 5, productID: 6) == nil)
      #expect(store.persona(vendorID: 1, productID: 2)?.identity != nil)
      #expect(store.files.map(\.url.lastPathComponent) == ["broken.json", "stick.json"])
    }
  }

  @Test
  func settingAnOverrideKeepsTheIdentityOfTheMatchingPersona() throws {
    try withDirectory { directory in
      try write(
        persona(vendorID: 1, productID: 2, identity: Self.identityJSON),
        named: "stick.json",
        in: directory
      )
      let store = Store(directory: directory)

      try store.set(.xboxOneSBluetooth, vendorID: 1, productID: 2)

      let found = try #require(store.persona(vendorID: 1, productID: 2))
      #expect(found.descriptor == .xboxOneSBluetooth)
      #expect(found.identity?.productName == "Arcade Stick")
      #expect(store.files.map(\.url.lastPathComponent) == ["stick.json"])
    }
  }

  @Test
  func anUnreadableDirectoryIsAnErrorAndWritesFail() throws {
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
