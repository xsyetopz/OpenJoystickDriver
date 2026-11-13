import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct GenerateCommandTests {
  private let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("ojd-generate-\(UUID().uuidString)", isDirectory: true)

  init() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  /// Writes `source` as a script in the test folder and returns its path.
  private func script(_ source: String, _ name: String = "script.js") throws -> String {
    let url = folder.appendingPathComponent(name)
    try Data(source.utf8).write(to: url)
    return url.path
  }

  /// Runs `ojd generate` with the helper of the built executable.
  private func run(_ arguments: [String]) async -> CLIRun {
    await GenerateCommand.$helper.withValue(GenerateHelperLocation.executable) {
      await CLIRun.run(["generate"] + arguments)
    }
  }

  @Test
  func endlessScriptEndedAtTimeLimit() async throws {
    let path = try script("while (true) {}")
    let start = Date()

    let result = await run([path, "--timeout", "1"])

    #expect(result.code == 1, "\(result.standardError)")
    #expect(result.standardError.contains("error[E2010]"), "\(result.standardError)")
    #expect(Date().timeIntervalSince(start) < 20)
  }

  /// The JavaScript object of a Controller record for the product `productID` of an unknown vendor.
  private static func record(_ productID: Int, extra: String = "") -> String {
    """
    { apiVersion: "\(OpenJoystickDriverAPI.version)", kind: "Controller", vendorID: 0xFFF1,
      productID: \(productID), modes: [{ id: "default", protocol: { family: "XboxGIP" } }]\(extra) }
    """
  }

  /// The names of the files in the folder `name` of the test folder.
  private func files(_ name: String = "out") -> [String] {
    let url = folder.appendingPathComponent(name)
    return ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
  }

  private var out: String { folder.appendingPathComponent("out").path }

  @Test(arguments: [
    ("function generate() { return null; }", "must return one document"),
    ("function generate() {}", "must return one document"),
    ("function generate() { return 3; }", "must return one document"),
    ("function generate() { return []; }", "must return one document"),
    ("function generate() { return [1]; }", "must return one document"),
    ("function generate() { return () => 1; }", "must return one document"),
    ("var generate = 3;", "calling the function failed"),
    ("var other = 1;", "defines no generate function"),
  ])
  func resultNoDocumentRefused(source: String, message: String) async throws {
    let path = try script(source)

    let result = await run([path, "--output", out])

    #expect(result.code == 1, "\(result.standardError)")
    #expect(result.standardError.contains("E2011"), "\(result.standardError)")
    #expect(files().isEmpty)
    if message != "calling the function failed" {
      #expect(result.standardError.contains(message), "\(result.standardError)")
    }
  }

  @Test(arguments: [
    ("\n\nthrow new Error('boom');\nfunction generate() {}", "line 3", "boom"),
    ("function generate() {\n  throw new Error('inside');\n}", "line 2", "inside"),
    (
      "function generate() {\n\n  return fetch('https://example.com');\n}", "line 3",
      "ReferenceError"
    ),
    ("function generate( {", "line 1", "SyntaxError"),
    ("const pad: number = 1;\nfunction generate() {}", "line 1", "SyntaxError"),
  ])
  func scriptErrorReportedWithItsLine(source: String, line: String, message: String) async throws {
    let path = try script(source)

    let result = await run([path, "--output", out])

    #expect(result.code == 1, "\(result.standardError)")
    #expect(result.standardError.contains(line), "\(result.standardError)")
    #expect(result.standardError.contains(message), "\(result.standardError)")
    #expect(files().isEmpty)
  }

  @Test
  func thrownStringReportedWithoutLine() async throws {
    let path = try script("function generate() { throw 'plain'; }")

    let result = await run([path])

    #expect(result.code == 1)
    #expect(result.standardError.contains("failed: plain"), "\(result.standardError)")
  }

  @Test
  func missingScriptRefused() async {
    let result = await run([folder.appendingPathComponent("none.js").path])

    #expect(result.code == 1)
    #expect(result.standardError.contains("E2016"), "\(result.standardError)")
  }

  @Test
  func recordWrittenWithStoreNameAndIntegerTypes() async throws {
    let path = try script("function generate() { return \(Self.record(1)); }")

    let result = await run([path, "--output", out])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(files() == ["fff1-0001.plist"])
    let text = try String(
      contentsOf: folder.appendingPathComponent("out/fff1-0001.plist"),
      encoding: .utf8
    )
    #expect(text.contains("<key>vendorID</key>\n\t<integer>65521</integer>"), "\(text)")
    #expect(result.standardOutput.contains("Created"), "\(result.standardOutput)")
  }

  @Test
  func listOfRecordsWritesOneFileEach() async throws {
    let record = Self.record(0).replacingOccurrences(of: "productID: 0", with: "productID: id")
    let path = try script(
      "function generate() { return [1, 2, 3].map(function (id) { return \(record); }); }"
    )

    let result = await run([path, "--output", out, "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(files() == ["fff1-0001.plist", "fff1-0002.plist", "fff1-0003.plist"])
    let items = try #require(try result.json()["items"] as? [[String: Any]])
    #expect(items.compactMap { $0["status"] as? String } == ["Created", "Created", "Created"])
  }

  @Test
  func oneInvalidDocumentWritesNoFileAndNamesDocumentAndKeyPath() async throws {
    let broken = Self.record(2).replacingOccurrences(of: "vendorID: 0xFFF1", with: "vendorID: 'x'")
    let path = try script(
      "function generate() { return [\(Self.record(1)), \(broken), \(Self.record(3))]; }"
    )

    let result = await run([path, "--output", out])

    #expect(result.code == 1, "\(result.standardError)")
    #expect(result.standardError.contains("E2011"), "\(result.standardError)")
    #expect(result.standardError.contains("Document 2"), "\(result.standardError)")
    #expect(result.standardError.contains("vendorID"), "\(result.standardError)")
    #expect(files().isEmpty)
  }

  @Test
  func nullInsideDocumentNamesItsKeyPath() async throws {
    let path = try script(
      "function generate() { return \(Self.record(1, extra: ", note: { deep: [1, null] }")); }"
    )

    let result = await run([path, "--output", out])

    #expect(result.code == 1)
    #expect(result.standardError.contains("note.deep[1] is null"), "\(result.standardError)")
    #expect(files().isEmpty)
  }

  @Test(arguments: [
    #"{ apiVersion: "x", kind: "Settings" }"#, #"{ apiVersion: "x" }"#,
  ])
  func kindNoGeneratorWritesRefused(document: String) async throws {
    let path = try script("function generate() { return \(document); }")

    let result = await run([path, "--output", out])

    #expect(result.code == 1)
    #expect(result.standardError.contains("kind"), "\(result.standardError)")
    #expect(files().isEmpty)
  }

  @Test
  func twoDocumentsForOneFileWriteNothing() async throws {
    let path = try script("function generate() { return [\(Self.record(1)), \(Self.record(1))]; }")

    let result = await run([path, "--output", out])

    #expect(result.code == 1)
    #expect(result.standardError.contains("Documents 1 and 2"), "\(result.standardError)")
    #expect(files().isEmpty)
  }

  @Test
  func equalFileUnchangedAndDifferingFileStopsRunUnlessReplaced() async throws {
    let path = try script("function generate() { return [\(Self.record(1)), \(Self.record(2))]; }")
    _ = await run([path, "--output", out])
    let first = folder.appendingPathComponent("out/fff1-0001.plist")
    let second = folder.appendingPathComponent("out/fff1-0002.plist")

    let again = await run([path, "--output", out])
    #expect(again.code == 0, "\(again.standardError)")
    #expect(again.standardOutput.components(separatedBy: "Unchanged").count == 3)

    try Data("edited".utf8).write(to: second)
    try FileManager.default.removeItem(at: first)
    let stopped = await run([path, "--output", out])
    #expect(stopped.code == 1, "\(stopped.standardError)")
    #expect(stopped.standardError.contains(second.path), "\(stopped.standardError)")
    #expect(stopped.standardError.contains("E2016"), "\(stopped.standardError)")
    #expect(files() == ["fff1-0002.plist"])
    #expect(try String(contentsOf: second, encoding: .utf8) == "edited")

    let replaced = await run([path, "--output", out, "--replace"])
    #expect(replaced.code == 0, "\(replaced.standardError)")
    #expect(files() == ["fff1-0001.plist", "fff1-0002.plist"])
    #expect(try String(contentsOf: second, encoding: .utf8) != "edited")
  }

  @Test
  func withoutOutputFolderDocumentsOnlyPrinted() async throws {
    let path = try script("function generate() { return \(Self.record(1)); }")

    let human = await run([path])
    let json = await run([path, "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.contains("<integer>65521</integer>"), "\(human.standardOutput)")
    #expect(json.code == 0, "\(json.standardError)")
    let items = try #require(try json.json()["items"] as? [[String: Any]])
    #expect(items.first?["status"] as? String == "NotWritten")
    #expect(files().isEmpty)
  }

  @Test
  func scriptOnWikiPageWritesRecordsOJDLoads() async throws {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { root.deleteLastPathComponent() }
    let page = try String(
      contentsOf: root.appendingPathComponent("wiki/Generating-Documents-with-Scripts.md"),
      encoding: .utf8
    )
    let opening = try #require(page.range(of: "```javascript\n"))
    let closing = try #require(page.range(of: "\n```", range: opening.upperBound..<page.endIndex))
    let path = try script(String(page[opening.upperBound..<closing.lowerBound]), "pads.js")

    let result = await run([path, "--output", out])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(files() == ["1209-0001.plist", "1209-0002.plist", "1209-0003.plist"])
    for name in files() {
      let data = try Data(contentsOf: folder.appendingPathComponent("out/\(name)"))
      #expect(throws: Never.self) { _ = try ControllerRecordSet.validate(data) }
    }
  }
}
