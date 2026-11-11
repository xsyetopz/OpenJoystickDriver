import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// The repository checks over files in a scratch directory.
@Suite
struct RepositoryValidationTests {
  private static let protocols = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/OpenJoystickDriverKit/Resources/Protocols")

  private static func scratch(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RepositoryValidationTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private static func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try PropertyListFixture.bytes(json: text).write(to: url)
  }

  /// A directory named `name`, which the checks find as a `.plist` file they cannot read.
  private static func unreadable(_ name: String, in directory: URL) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  // MARK: a file that cannot be read is fileAccessFailed

  @Test
  func aRecordPatchOrDescriptionThatCannotBeReadIsAFileAccessFailure() throws {
    try Self.scratch { directory in
      let records = directory.appendingPathComponent("records")
      let patches = directory.appendingPathComponent("patches")
      let descriptions = directory.appendingPathComponent("descriptions")
      let record = try Self.unreadable("04d2-162e.plist", in: records)
      let patch = try Self.unreadable("all.patch.plist", in: patches)
      let description = try Self.unreadable("xbox-xusb.plist", in: descriptions)

      func unreadableFiles(_ problems: [RepositoryProblem]) -> [String] {
        problems.filter { $0.code == .fileAccessFailed }.map {
          URL(fileURLWithPath: $0.file).lastPathComponent
        }
      }

      let recordProblems = RepositoryValidation.controllers(in: records)
      #expect(unreadableFiles(recordProblems) == [record.lastPathComponent])
      #expect(recordProblems.count == 1)

      let patchProblems = RepositoryValidation.applyPatches(
        controllers: records,
        patches: patches,
        output: directory.appendingPathComponent("out")
      )
      #expect(
        Set(unreadableFiles(patchProblems))
          == [patch.lastPathComponent, record.lastPathComponent]
      )
      #expect(patchProblems.count == 2)

      let descriptionProblems = RepositoryValidation.descriptions(in: descriptions)
      #expect(unreadableFiles(descriptionProblems) == [description.lastPathComponent])
    }
  }

  @Test
  func aProfileOrPersonaThatCannotBeReadIsAFileAccessFailure() throws {
    try Self.scratch { directory in
      let missing = directory.appendingPathComponent("missing.plist")
      let profile = try #require(RepositoryValidation.profile(at: missing))
      #expect(profile.file == missing.path)
      #expect(profile.code == .fileAccessFailed)
      let persona = try #require(RepositoryValidation.virtualDevice(at: missing))
      #expect(persona.code == .fileAccessFailed)

      let invalid = directory.appendingPathComponent("invalid.plist")
      try Self.write(#"{"apiVersion": "ojd/v0", "kind": "Profile", "name": "Pad"}"#, to: invalid)
      #expect(RepositoryValidation.profile(at: invalid)?.code == .unsupportedAPIVersion)
    }
  }

  @Test
  func textThatIsNotAPropertyListIsAnInvalidRecord() throws {
    try Self.scratch { directory in
      try Self.write("{", to: directory.appendingPathComponent("04d2-162e.plist"))
      let problems = RepositoryValidation.controllers(in: directory)
      #expect(problems.map(\.code) == [.invalidDocumentForm])
    }
  }

  // MARK: one identity has one record

  @Test
  func aSecondRecordOfOneIdentityIsReportedWithBothFiles() throws {
    try Self.scratch { directory in
      let text =
        #"{"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Controller","#
        + #" "vendorID": 13623, "productID": 4226, "modes": [{"id": "default","#
        + #" "protocol": {"family": "XboxGIP"}}]}"#
      let first = directory.appendingPathComponent("3537/3537-1082.plist")
      let second = directory.appendingPathComponent("contributed/3537-1082.plist")
      try Self.write(text, to: first)
      try Self.write(text, to: second)
      let problems = RepositoryValidation.controllers(in: directory)
      let problem = try #require(
        problems.first { $0.message.contains("duplicate") },
        "\(problems.map(\.message))"
      )
      #expect(problems.count == 1)
      #expect(problem.file.hasSuffix("/contributed/3537-1082.plist"))
      #expect(problem.message.contains("3537:1082"))
      #expect(problem.message.contains(first.path))
    }
  }

  // MARK: descriptions come in family order

  @Test
  func descriptionProblemsComeInFamilyOrderWithAMissingFileAtItsFamilysPlace() throws {
    try Self.scratch { directory in
      for name in try FileManager.default.contentsOfDirectory(atPath: Self.protocols.path) {
        try FileManager.default.copyItem(
          at: Self.protocols.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      // Family order is XID, XUSB, GIP; file-name order is GIP, XID, XUSB.
      for stem in ["xbox-xid", "xbox-gip"] {
        let url = directory.appendingPathComponent("\(stem).plist")
        var object = try PropertyListFixture.dictionary(at: url)
        object["unknownField"] = 1
        try PropertyListFixture.data(tree: object).write(to: url)
      }
      try FileManager.default.removeItem(at: directory.appendingPathComponent("xbox-xusb.plist"))

      let problems = RepositoryValidation.descriptions(in: directory)
      #expect(
        problems.map { URL(fileURLWithPath: $0.file).lastPathComponent }
          == ["xbox-xid.plist", "xbox-xusb.plist", "xbox-gip.plist"]
      )
      #expect(
        problems.map(\.code) == [
          .invalidProtocolDescription, .invalidProtocolDescription, .invalidProtocolDescription,
        ]
      )
      #expect(problems[1].message == "xbox-xusb.plist is missing from \(directory.path)")
    }
  }

  @Test
  func aDescriptionFileThatNamesNoFamilyIsReportedAfterTheFamilies() throws {
    try Self.scratch { directory in
      for name in try FileManager.default.contentsOfDirectory(atPath: Self.protocols.path) {
        try FileManager.default.copyItem(
          at: Self.protocols.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      try Self.write("{}", to: directory.appendingPathComponent("aaa-extra.plist"))
      let problems = RepositoryValidation.descriptions(in: directory)
      #expect(
        problems.map { URL(fileURLWithPath: $0.file).lastPathComponent } == ["aaa-extra.plist"]
      )
    }
  }

  @Test
  func aSecondFileThatNamesAFamilyIsReportedAndNotLoaded() throws {
    try Self.scratch { directory in
      for name in try FileManager.default.contentsOfDirectory(atPath: Self.protocols.path) {
        try FileManager.default.copyItem(
          at: Self.protocols.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      let first = directory.appendingPathComponent("xbox-gip.plist")
      let second = directory.appendingPathComponent("zz/xbox-gip.plist")
      try FileManager.default.createDirectory(
        at: second.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(at: first, to: second)
      let problems = RepositoryValidation.descriptions(in: directory)
      #expect(problems.count == 1)
      #expect(problems.first?.file.hasSuffix("/zz/xbox-gip.plist") == true)
      #expect(problems.first?.code == .invalidProtocolDescription)
      #expect(problems.first?.message.hasSuffix("/xbox-gip.plist") == true)
      #expect(problems.first?.message.contains("/zz/") == false)
      // Files of one name are taken in path order: the file under the directory itself is
      // kept. The URLs' order does not decide which file is kept.
      let urls = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".plist") }.reversed()
        .map { directory.appendingPathComponent($0) }
      let catalog = ProtocolDescription.loadCatalog(Array(urls), missing: directory.path)
      #expect(catalog.problems.map(\.file).map { $0.hasSuffix("/zz/xbox-gip.plist") } == [true])
    }
  }

  // MARK: the bundled failure keeps the code

  @Test
  func aBundledRecordFailureLeadsWithTheFileAndTheCodeOfTheRule() throws {
    try Self.scratch { directory in
      let text =
        #"{"apiVersion": "ojd/v0", "kind": "Controller", "vendorID": 1234, "productID": 5678}"#
      let url = directory.appendingPathComponent("04d2-162e.plist")
      try Self.write(text, to: url)
      let problem = try #require(ControllerRecordSet.loadCatalog([url]).problems.first)
      #expect(problem.code == .unsupportedAPIVersion)
      let failure = ControllerRecordSet.bundledFailure(problem)
      #expect(failure.code == .invalidControllerRecord)
      #expect(failure.description == "\(url.path): E5001: \(problem.message)")
      #expect(failure.description.contains("E5001: apiVersion ojd/v0 is not supported"))
    }
  }
}
