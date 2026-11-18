import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private final class BundleAnchor {}

/// The built tool is not next to the test bundle; run `swift build --build-tests` first.
private struct MissingTool: Error, CustomStringConvertible {
  let path: String
  var description: String {
    "OJDRepositoryTool is not built at \(path); run swift build --build-tests"
  }
}

/// Runs the built `OJDRepositoryTool` on files in a scratch directory and compares each problem
/// with the code and reason that the Kit check reports for the same file.
@Suite(.serialized)
struct OJDRepositoryToolTests {
  struct Result {
    let status: Int32
    let standardOutput: String
    let standardError: String

    /// The problems printed, one JSON object per line.
    func problems() throws -> [[String: Any]] {
      try standardOutput.split(separator: "\n").map {
        try #require(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
      }
    }
  }

  private static let kitResources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/OpenJoystickDriverKit/Resources")
  private static let patchResources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/ControllerPatches")

  private static var tool: URL {
    get throws {
      // The tool is built into the folder that holds this test bundle.
      let bundle = Bundle(for: BundleAnchor.self)
      let tool = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent(
        "OJDRepositoryTool"
      )
      guard FileManager.default.fileExists(atPath: tool.path) else {
        throw MissingTool(path: tool.path)
      }
      return tool
    }
  }

  static func run(_ arguments: [String]) throws -> Result {
    let process = Process()
    process.executableURL = try tool
    process.arguments = arguments
    // The tool writes into files, not pipes, so neither stream can fill and block it while the
    // test waits on the other.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OJDRepositoryToolTests-run-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputFile = directory.appendingPathComponent("out")
    let errorFile = directory.appendingPathComponent("err")
    FileManager.default.createFile(atPath: outputFile.path, contents: nil)
    FileManager.default.createFile(atPath: errorFile.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputFile)
    let errors = try FileHandle(forWritingTo: errorFile)
    defer {
      try? output.close()
      try? errors.close()
    }
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let standardOutput = try Data(contentsOf: outputFile)
    let standardError = try Data(contentsOf: errorFile)
    return Result(
      status: process.terminationStatus,
      standardOutput: try #require(String(data: standardOutput, encoding: .utf8)),
      standardError: try #require(String(data: standardError, encoding: .utf8))
    )
  }

  static func scratch(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OJDRepositoryToolTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private static func resource(_ path: String) throws -> Data {
    try Data(contentsOf: kitResources.appendingPathComponent(path))
  }

  private static let recordPath = "Controllers/045e/045e-028e.plist"

  // MARK: records

  @Test
  func validRecordDirectoryHasNoProblem() throws {
    try Self.scratch { directory in
      try Self.resource(Self.recordPath).write(
        to: directory.appendingPathComponent("045e-028e.plist")
      )
      let result = try Self.run(["validate", "controllers", directory.path])
      #expect(result.status == 0)
      #expect(result.standardOutput.isEmpty)
    }
  }

  @Test
  func bundledRecordsHaveNoProblem() throws {
    let result = try Self.run([
      "validate", "controllers", Self.kitResources.appendingPathComponent("Controllers").path,
    ])
    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func recordRuleFailureHasCodeThatRecordSetReports() throws {
    try Self.scratch { directory in
      var object = try #require(
        PropertyListFixture.tree(Self.resource(Self.recordPath)) as? [String: Any]
      )
      object["apiVersion"] = "ojd/v0"
      let data = try PropertyListFixture.data(tree: object)
      try data.write(to: directory.appendingPathComponent("045e-028e.plist"))
      let expected = try #require(throws: (any Error).self) {
        try ControllerRecordSet.validate(data)
      }
      let result = try Self.run(["validate", "controllers", directory.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(try result.problems().count == 1)
      #expect(problem["code"] as? String == ControllerRecordSet.problemCode(expected)?.rawValue)
      #expect(problem["code"] as? String == ErrorCode.unsupportedAPIVersion.rawValue)
      #expect(
        problem["message"] as? String
          == ControllerRecordSet.problemDescription(
            expected,
            includingCode: false,
            document: "record"
          )
      )
      #expect((problem["file"] as? String)?.hasSuffix("045e-028e.plist") == true)
    }
  }

  @Test
  func recordNoXMLPropertyListGetsReasonOfRecordSet() throws {
    let tree = try PropertyListFixture.tree(Self.resource(Self.recordPath))
    let faulty: [(reason: String, data: Data)] = [
      ("holds JSON text", try JSONSerialization.data(withJSONObject: tree)),
      (
        "is a binary property list",
        try PropertyListSerialization.data(fromPropertyList: tree, format: .binary, options: 0)
      ),
    ]
    for (reason, data) in faulty {
      try Self.scratch { directory in
        try data.write(to: directory.appendingPathComponent("045e-028e.plist"))
        let expected = try #require(throws: (any Error).self) {
          try ControllerRecordSet.validate(data)
        }
        let result = try Self.run(["validate", "controllers", directory.path])
        let problem = try #require(try result.problems().first, "\(reason)")
        #expect(result.status == 1, "\(reason)")
        #expect(
          problem["code"] as? String == ControllerRecordSet.problemCode(expected)?.rawValue,
          "\(reason)"
        )
        #expect(
          problem["message"] as? String
            == "045e-028e.plist \(reason); save it as an XML property list",
          "\(reason)"
        )
      }
    }
  }

  @Test
  func recordWhoseFileNameIsNotItsOwnIsProblem() throws {
    try Self.scratch { directory in
      try Self.resource(Self.recordPath).write(
        to: directory.appendingPathComponent("045e-0000.plist")
      )
      let result = try Self.run(["validate", "controllers", directory.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(problem["code"] as? String == ErrorCode.invalidControllerRecord.rawValue)
      #expect(problem["message"] as? String == "filename must be 045e-028e.plist")
    }
  }

  // MARK: descriptions

  @Test
  func bundledDescriptionsHaveNoProblem() throws {
    let result = try Self.run([
      "validate", "descriptions", Self.kitResources.appendingPathComponent("Protocols").path,
    ])
    #expect(result.status == 0)
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func descriptionFailureHasCodeThatDecodeReports() throws {
    try Self.scratch { directory in
      let source = Self.kitResources.appendingPathComponent("Protocols")
      for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try FileManager.default.copyItem(
          at: source.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      let name = "xbox-xusb.plist"
      var object = try PropertyListFixture.dictionary(at: directory.appendingPathComponent(name))
      object["unknownField"] = 1
      let data = try PropertyListFixture.data(tree: object)
      try data.write(to: directory.appendingPathComponent(name))
      let expected = try #require(throws: ProtocolDescriptionProblem.self) {
        try ProtocolDescription.decode(data, fileName: name)
      }
      let result = try Self.run(["validate", "descriptions", directory.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(try result.problems().count == 1)
      #expect(problem["code"] as? String == expected.code.rawValue)
      #expect(problem["message"] as? String == expected.detail)
    }
  }

  @Test
  func familyWithoutDescriptionFileIsProblem() throws {
    try Self.scratch { directory in
      let result = try Self.run(["validate", "descriptions", directory.path])
      #expect(result.status == 1)
      #expect(try result.problems().count == PhysicalProtocolID.allCases.count)
      #expect(
        try result.problems().allSatisfy {
          $0["code"] as? String == ErrorCode.invalidProtocolDescription.rawValue
        }
      )
    }
  }

  @Test
  func secondFileThatNamesFamilyIsProblem() throws {
    try Self.scratch { directory in
      let source = Self.kitResources.appendingPathComponent("Protocols")
      for name in try FileManager.default.contentsOfDirectory(atPath: source.path) {
        try FileManager.default.copyItem(
          at: source.appendingPathComponent(name),
          to: directory.appendingPathComponent(name)
        )
      }
      let nested = directory.appendingPathComponent("zz", isDirectory: true)
      try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
      let name = "xbox-xusb.plist"
      try FileManager.default.copyItem(
        at: directory.appendingPathComponent(name),
        to: nested.appendingPathComponent(name)
      )
      let result = try Self.run(["validate", "descriptions", directory.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(try result.problems().count == 1)
      #expect(problem["code"] as? String == ErrorCode.invalidProtocolDescription.rawValue)
      #expect((problem["file"] as? String)?.hasSuffix("/zz/\(name)") == true)
      #expect((problem["message"] as? String)?.hasSuffix("/\(name)") == true)
    }
  }

  // MARK: profiles and virtual devices

  private static let profile = #"""
    {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "Profile", "name": "Pad"}
    """#

  @Test
  func validAndInvalidProfile() throws {
    try Self.scratch { directory in
      let valid = RemappingProfile(
        name: "Portable",
        device: RemappingDeviceScope(vendorID: 1118, productID: 654),
        applicationScope: .global,
        bindings: [
          RemappingBinding(
            source: .button(.south),
            destination: .keyboard(key: .space, modifiers: [])
          )
        ]
      )
      let good = directory.appendingPathComponent("good.plist")
      let bad = directory.appendingPathComponent("bad.plist")
      try RemappingProfileFileStore.write(valid, to: good)
      let invalid = PropertyListFixture.bytes(
        json: #"{"apiVersion": "ojd/v0", "kind": "Profile", "name": "Pad"}"#
      )
      try invalid.write(to: bad)
      #expect(try Self.run(["validate", "profiles", good.path]).status == 0)

      let expected = try #require(throws: (any Error).self) {
        try RemappingProfileFileStore.load(from: invalid)
      }
      let result = try Self.run(["validate", "profiles", good.path, bad.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(try result.problems().count == 1)
      #expect(problem["file"] as? String == bad.path)
      #expect(
        problem["code"] as? String == RemappingProfileFileStore.problemCode(expected).rawValue
      )
      #expect(problem["code"] as? String == ErrorCode.unsupportedAPIVersion.rawValue)
    }
  }

  @Test
  func validAndInvalidPersona() throws {
    try Self.scratch { directory in
      let document = { (persona: String) in
        PropertyListFixture.bytes(
          json: """
            {"apiVersion": "openjoystickdriver/v1alpha3", "kind": "VirtualDevice",
              "match": {"vendorID": 1118, "productID": 654}, "persona": "\(persona)"}
            """
        )
      }
      let good = directory.appendingPathComponent("good.plist")
      let bad = directory.appendingPathComponent("bad.plist")
      try document("Generic").write(to: good)
      try document("Nothing").write(to: bad)
      #expect(try Self.run(["validate", "virtual-devices", good.path]).status == 0)

      let expected = try #require(throws: (any Error).self) {
        try VirtualHIDProfileOverrideStore.parse(document("Nothing"))
      }
      let result = try Self.run(["validate", "virtual-devices", directory.path])
      let problem = try #require(try result.problems().first)
      #expect(result.status == 1)
      #expect(try result.problems().count == 1)
      #expect((problem["file"] as? String)?.hasSuffix("/bad.plist") == true)
      #expect(problem["code"] as? String == ErrorCode.invalidControllerRecord.rawValue)
      #expect(ControllerRecordSet.problemCode(expected) == .invalidControllerRecord)
      #expect(
        problem["message"] as? String
          == ControllerRecordSet.problemDescription(
            expected,
            includingCode: false,
            document: "virtualDevice"
          )
      )
    }
  }

  // MARK: patches

  @Test
  func applyPatchesWritesEffectiveRecord() throws {
    try Self.scratch { directory in
      let records = directory.appendingPathComponent("records/057e")
      let patches = directory.appendingPathComponent("patches/057e")
      let output = directory.appendingPathComponent("out")
      try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: patches, withIntermediateDirectories: true)
      let effective = try Self.resource("Controllers/057e/057e-2066.plist")
      var unpatched = try #require(PropertyListFixture.tree(effective) as? [String: Any])
      unpatched["bluetoothLE"] = nil
      try PropertyListFixture.data(tree: unpatched)
        .write(to: records.appendingPathComponent("057e-2066.plist"))
      try Data(
        contentsOf: Self.patchResources.appendingPathComponent("057e/057e-2066.patch.plist")
      ).write(to: patches.appendingPathComponent("057e-2066.patch.plist"))

      let result = try Self.run([
        "apply-patches", "--controllers", directory.appendingPathComponent("records").path,
        "--patches", directory.appendingPathComponent("patches").path, "--out", output.path,
      ])
      #expect(result.status == 0)
      #expect(result.standardOutput.isEmpty)
      let written = try Data(contentsOf: output.appendingPathComponent("057e/057e-2066.plist"))
      #expect(
        try DocumentCoder.write(PropertyListFixture.tree(written))
          == DocumentCoder.write(PropertyListFixture.tree(effective))
      )

      // Over the written record, the same patch changes nothing and writes no output.
      let again = try Self.run([
        "apply-patches", "--controllers",
        output.deletingLastPathComponent().appendingPathComponent("out").path,
        "--patches", directory.appendingPathComponent("patches").path,
        "--out", directory.appendingPathComponent("again").path,
      ])
      let problem = try #require(try again.problems().first)
      #expect(again.status == 1)
      #expect(problem["code"] as? String == ErrorCode.invalidControllerRecord.rawValue)
      let model = ControllerModelID(vendorID: 0x057e, productID: 0x2066)
      #expect(problem["message"] as? String == "the patch changes nothing in \(model)")
      #expect(
        !FileManager.default.fileExists(atPath: directory.appendingPathComponent("again").path)
      )
    }
  }

  /// Writes `record` and `patches` (relative path and text) under a scratch directory and runs
  /// `apply-patches` on them.
  private static func applyPatches(
    record: String,
    patches: [String: String],
    check: (Result, URL) throws -> Void
  ) throws {
    try scratch { directory in
      let records = directory.appendingPathComponent("records/057e")
      try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
      try PropertyListFixture.data(json: record).write(
        to: records.appendingPathComponent("057e-2066.plist")
      )
      for (path, text) in patches {
        let file = directory.appendingPathComponent("patches").appendingPathComponent(path)
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try PropertyListFixture.data(json: text).write(to: file)
      }
      let result = try run([
        "apply-patches", "--controllers", directory.appendingPathComponent("records").path,
        "--patches", directory.appendingPathComponent("patches").path,
        "--out", directory.appendingPathComponent("out").path,
      ])
      try check(result, directory.appendingPathComponent("out"))
    }
  }

  private static func patchDocument(selector: String, body: String) -> String {
    """
    {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
      "selector": \(selector), "patch": \(body)}
    """
  }

  private static let upstream = """
    {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
      "vendorID": 1406, "productID": 8294,
    "modes": [{"id": "default", "protocol": {"family": "HIDDescriptor"}}],
    "tuning": {"stickDeadzone": 0.10, "frameQueueCapacity": 4}}
    """
  private static let identity = #"{"vendorID": 1406, "productID": 8294}"#

  @Test
  func applyPatchesKeepsValuesOfRecordNoPatchChanges() throws {
    try Self.applyPatches(
      record: Self.upstream,
      patches: [
        "057e/057e-2066.patch.plist": Self.patchDocument(
          selector: Self.identity,
          body: #"{"tuning": {"frameQueueCapacity": 8}}"#
        )
      ]
    ) { result, output in
      #expect(result.status == 0, "\(result.standardOutput)")
      let tree = try PropertyListFixture.dictionary(
        at: output.appendingPathComponent("057e/057e-2066.plist")
      )
      let tuning = try #require(tree["tuning"] as? [String: Any])
      #expect(tuning["stickDeadzone"] as? Double == 0.10)
      #expect(tuning["frameQueueCapacity"] as? Int == 8)
    }
  }

  @Test
  func applyPatchesRefusesPatchDeeperThanLayoutAndWritesNothing() throws {
    let patch = Self.patchDocument(
      selector: Self.identity,
      body: #"{"tuning": {"frameQueueCapacity": 8}}"#
    )
    try Self.applyPatches(
      record: Self.upstream,
      patches: [
        "057e/more/057e-2066.patch.plist": patch,
        "057e-2066.patch.plist": patch,
      ]
    ) { result, output in
      #expect(result.status == 1)
      let messages = try result.problems().compactMap { $0["message"] as? String }
      #expect(messages.contains("the patch path must be 057e/057e-2066.patch.plist"), "\(messages)")
      #expect(messages.count == 2, "\(messages)")
      #expect(!FileManager.default.fileExists(atPath: output.path))
    }
  }

  @Test
  func applyPatchesRefusesUnknownFieldAndPatchOfNoRecord() throws {
    try Self.applyPatches(
      record: Self.upstream,
      patches: [
        "057e/057e-2066.patch.plist": Self.patchDocument(
          selector: Self.identity,
          body: #"{"notAField": "hid"}"#
        ),
        "057e/057e-2067.patch.plist": Self.patchDocument(
          selector: #"{"vendorID": 1406, "productID": 8295}"#,
          body: #"{"tuning": {"frameQueueCapacity": 8}}"#
        ),
      ]
    ) { result, output in
      #expect(result.status == 1)
      let messages = try result.problems().compactMap { $0["message"] as? String }
      #expect(messages.contains { $0.contains("patch must hold modes") }, "\(messages)")
      #expect(messages.contains { $0.contains("is not a known controller") }, "\(messages)")
      #expect(!FileManager.default.fileExists(atPath: output.path))
    }
  }

  // MARK: usage

  @Test
  func callThatToolRefusesExitsWithUsageStatusAndNamesCall() throws {
    let calls: [(arguments: [String], message: String)] = [
      ([], "no subcommand given"),
      (["frobnicate"], "unknown subcommand frobnicate"),
      (["validate"], "validate needs a kind"),
      (["validate", "widgets", "x"], "unknown validate kind widgets"),
      (
        ["validate", "controllers", "/nonexistent-directory"],
        "/nonexistent-directory is not a directory"
      ),
      (["validate", "profiles"], "no path given"),
      (
        ["validate", "profiles", "/nonexistent-profile.json"],
        "/nonexistent-profile.json does not exist"
      ),
      (["apply-patches", "--controllers", "a"], "--patches is required"),
    ]
    for call in calls {
      let result = try Self.run(call.arguments)
      #expect(result.status == 64, "\(call.arguments)")
      #expect(result.standardOutput.isEmpty, "\(call.arguments)")
      #expect(
        result.standardError.contains("OJDRepositoryTool: \(call.message)"),
        "\(call.arguments)"
      )
    }
  }

  // MARK: facts

  @Test
  func factsPrintConstantsThatSwiftOwns() throws {
    let result = try Self.run(["facts"])
    #expect(result.status == 0)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )
    #expect(object["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(
      object["commandLineExitStatuses"] as? [Int]
        == ErrorCode.commandLineExitStatuses.sorted().map(Int.init)
    )
    #expect(
      object["domainCodePrefixes"] as? [String: String]
        == Dictionary(
          uniqueKeysWithValues: ErrorCode.Domain.allCases.map { ($0.rawValue, $0.codePrefix) }
        )
    )
    #expect(object["schemaBase"] as? String == OpenJoystickDriverAPI.schemaBase)
    let english = Localization(preferredLanguages: [Localization.sourceLocalization])
    #expect(
      object["domainAreas"] as? [String: String]
        == Dictionary(
          uniqueKeysWithValues: ErrorCode.Domain.allCases.map {
            ($0.rawValue, english.string($0.areaKey))
          }
        )
    )
    #expect(object.count == 5)
  }

  @Test
  func kebabPrintsSpellingThatCommandLineNameGives() throws {
    let values = ["SystemHIDVisible", "ExclusiveRawUSB", "NotFound"]
    let result = try Self.run(["kebab"] + values)
    #expect(result.status == 0)
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: String]
    )
    #expect(
      object == Dictionary(uniqueKeysWithValues: values.map { ($0, CommandLineName.kebab($0)) })
    )
  }

  @Test
  func factCallThatToolRefusesExitsWith64() throws {
    for arguments in [["facts", "extra"], ["kebab"]] {
      let result = try Self.run(arguments)
      #expect(result.status == 64, "\(arguments)")
      #expect(result.standardOutput.isEmpty, "\(arguments)")
    }
  }

  // MARK: property lists

  @Test
  func toPlistWritesCanonicalFormBesideJSONFileAndKeepsNumberTypes() throws {
    try Self.scratch { directory in
      let json = directory.appendingPathComponent("a.json")
      try Data(#"{"b": 2, "a": [1.5, 9007199254740993, true, "x"], "c": {}}"#.utf8).write(to: json)
      let result = try Self.run(["to-plist", json.path])
      #expect(result.status == 0)
      let data = try Data(contentsOf: directory.appendingPathComponent("a.plist"))
      let tree = try #require(try DocumentCoder.read(data, file: "a.plist") as? [String: Any])
      #expect(tree["b"] as? Int64 == 2)
      let list = try #require(tree["a"] as? [Any])
      #expect(list[0] as? Double == 1.5)
      #expect(list[1] as? Int64 == 9_007_199_254_740_993)
      #expect(try DocumentCoder.write(tree) == data)
      #expect(FileManager.default.fileExists(atPath: json.path))
    }
  }

  @Test
  func toPlistRefusesNullAndWritesNothing() throws {
    try Self.scratch { directory in
      let json = directory.appendingPathComponent("a.json")
      try Data(#"{"a": null}"#.utf8).write(to: json)
      let result = try Self.run(["to-plist", json.path])
      #expect(result.status == 64)
      #expect(
        !FileManager.default.fileExists(atPath: directory.appendingPathComponent("a.plist").path)
      )
    }
  }

  @Test
  func formatPlistRewritesFileInCanonicalForm() throws {
    try Self.scratch { directory in
      let file = directory.appendingPathComponent("a.plist")
      let loose = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>b</key><integer>1</integer>
        <key>a</key><string>x</string></dict></plist>
        """
      try Data(loose.utf8).write(to: file)
      #expect(try Self.run(["format-plist", file.path]).status == 0)
      let data = try Data(contentsOf: file)
      #expect(try DocumentCoder.write(DocumentCoder.read(data, file: "a.plist")) == data)
      #expect(try #require(String(bytes: data, encoding: .utf8)).contains("<key>a</key>"))
    }
  }
}
