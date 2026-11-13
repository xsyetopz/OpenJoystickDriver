import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct ControllerRecordWriterTests {
  /// A bundled `SonyDualShock4` record, a HID family.
  static let bundledHID = ControllerModelID(vendorID: 0x2C22, productID: 0x2000)
  /// A bundled `XboxGIP` record, a raw-USB family.
  static let bundledGIP = ControllerModelID(vendorID: 0x366C, productID: 0x0005)
  static let unbundled = ControllerModelID(vendorID: 0x1234, productID: 0xABCD)

  /// Runs `body` with the `Controllers` folder of a temporary application-support folder, whose
  /// `Packages` store is empty unless the test installs a package.
  static func withDirectory(_ body: (URL, ModPackageFixture) throws -> Void) throws {
    try ModPackageFixture.with { fixture in
      try FileManager.default.createDirectory(
        at: fixture.controllers,
        withIntermediateDirectories: true
      )
      try body(fixture.controllers, fixture)
    }
  }

  static func change(
    _ identity: ControllerModelID,
    to server: ControllerServer,
    in directory: URL
  ) throws -> ControllerRecordWriter.Change {
    try ControllerRecordWriter.change(
      server,
      for: identity,
      records: .load(userDirectory: directory),
      directory: directory
    )
  }

  static func change(
    _ edit: ControllerRecordWriter.TuningEdit,
    for target: ControllerRecordWriter.Target,
    in directory: URL
  ) throws -> ControllerRecordWriter.Change {
    try ControllerRecordWriter.change(
      edit,
      for: target,
      records: .load(userDirectory: directory),
      directory: directory
    )
  }

  static func write(
    _ edit: ControllerRecordWriter.TuningEdit,
    for target: ControllerRecordWriter.Target,
    in directory: URL
  ) throws {
    try ControllerRecordWriter.write(change(edit, for: target, in: directory))
  }

  static func fields(_ file: URL) throws -> [String: Any] {
    try #require(try object(Data(contentsOf: file))["patch"] as? [String: Any])
  }

  static func object(_ data: Data) throws -> [String: Any] {
    try #require(try PropertyListFixture.tree(data) as? [String: Any])
  }

  @Test
  func missingFileBecomesAPatchOfOnlyOwnership() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(Self.bundledHID, to: .ojd, in: directory)
      #expect(change.created)
      #expect(change.previousServer == .system)
      #expect(change.file.lastPathComponent == "2c22-2000.patch.plist")
      try ControllerRecordWriter.write(change)
      let written = try Self.object(Data(contentsOf: change.file))
      #expect(written["kind"] as? String == "ControllerPatch")
      let selector = try #require(written["selector"] as? [String: Int])
      #expect(selector == ["vendorID": 0x2C22, "productID": 0x2000])
      #expect(written["patch"] as? [String: String] == ["server": "OJD"])
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      #expect(loaded.records[Self.bundledHID]?.profile.server == .ojd)
      #expect(loaded.records[Self.bundledHID]?.fieldLayers["server"] == .user)
    }
  }

  @Test
  func existingFileKeepsItsOtherKeys() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      try PropertyListFixture.data(
        tree: ControllerPatch.document(
          selector: .identity(Self.bundledHID),
          body: ["server": "OJD", "tuning": ["stickDeadzone": 0.1]]
        )
      )
      .write(to: file)
      let change = try Self.change(Self.bundledHID, to: .system, in: directory)
      #expect(!change.created)
      #expect(change.previousServer == .ojd)
      try ControllerRecordWriter.write(change)
      let set = try #require(try Self.object(Data(contentsOf: file))["patch"] as? [String: Any])
      #expect(set["server"] as? String == "System")
      #expect(set["tuning"] as? [String: Double] == ["stickDeadzone": 0.1])
    }
  }

  /// A model that only an installed package has gets a patch over the package record, which
  /// keeps the package's other fields.
  @Test
  func packageOnlyModelGetsAPatchOverThePackageRecord() throws {
    try Self.withDirectory { directory, fixture in
      let record: [String: Any] = [
        "apiVersion": OpenJoystickDriverAPI.version, "kind": ControllerRecordDocument.kind,
        "vendorID": 0x1234,
        "productID": 0xABCD,
        "modes": [["id": "default", "protocol": ["family": "HIDDescriptor"]]],
      ]
      let package = try fixture.makePackage(
        controllers: [("1234-abcd.plist", try PropertyListFixture.data(tree: record))]
      )
      try fixture.store().install(package, replace: true)
      let change = try Self.change(Self.unbundled, to: .ojd, in: directory)
      #expect(change.created)
      try ControllerRecordWriter.write(change)
      let loaded = ControllerRecordSet.load(userDirectory: directory)
      let effective = try #require(loaded.records[Self.unbundled])
      #expect(effective.profile.server == .ojd)
      #expect(effective.fieldLayers == ["modes": .package, "server": .user])
      #expect(loaded.problems.isEmpty)
    }
  }

  @Test
  func invalidFileIsRefusedAndKept() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      try Data("{".utf8).write(to: file)
      #expect(
        throws: ControllerRecordWriter.Failure.invalidFile(
          "2c22-2000.patch.plist is not an XML property list"
        )
      ) { try Self.change(Self.bundledHID, to: .ojd, in: directory) }
      #expect(try Data(contentsOf: file) == Data("{".utf8))
    }
  }

  @Test
  func modelWithoutARecordIsRefused() throws {
    try Self.withDirectory { directory, _ in
      #expect(throws: ControllerRecordWriter.Failure.noRecord(Self.unbundled)) {
        try Self.change(Self.unbundled, to: .ojd, in: directory)
      }
    }
  }

  @Test
  func rawUSBModelIsRefused() throws {
    try Self.withDirectory { directory, _ in
      do {
        _ = try Self.change(Self.bundledGIP, to: .ojd, in: directory)
        Issue.record("a raw-USB model was accepted")
      } catch {
        guard case .invalidResult(let problem) = error as? ControllerRecordWriter.Failure
        else {
          Issue.record("unexpected failure \(error)")
          return
        }
        #expect(problem.contains("server"))
      }
    }
  }

  /// `change` computes the record; only `write` touches the directory, which is how
  /// `--dry-run` writes nothing.
  @Test
  func changeAloneWritesNothing() throws {
    try Self.withDirectory { directory, _ in
      let change = try Self.change(Self.bundledHID, to: .ojd, in: directory)
      #expect(!FileManager.default.fileExists(atPath: change.file.path))
      #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }
  }

  /// The written file is the canonical property list of the patch with only `server` changed.
  @Test
  func existingFileWrittenAsCanonicalPropertyList() throws {
    try Self.withDirectory { directory, _ in
      let file = directory.appendingPathComponent("2c22-2000.patch.plist")
      func data(_ server: String) throws -> Data {
        try PropertyListFixture.data(
          tree: ControllerPatch.document(
            selector: .identity(Self.bundledHID),
            body: ["tuning": ["stickDeadzone": 0.1], "server": server]
          )
        )
      }
      try data("OJD").write(to: file)
      let change = try Self.change(Self.bundledHID, to: .system, in: directory)
      #expect(change.data == (try data("System")))
    }
  }
}
