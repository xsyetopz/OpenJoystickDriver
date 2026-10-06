import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct RecordTestCommandTests {
  /// The bundled Xbox 360 wired pad, whose parser reads a 20-byte report.
  private static let identity = "045E:028E"

  /// A capture of an acknowledgement-sized packet that the parser ignores, a transmitted packet,
  /// and one input report with A held (button bit 12).
  private static let capture = """
    {"timestamp": 0, "direction": "tx", "hex": "01 03 00", "length": 3}
    {"timestamp": 1, "direction": "rx", "length": 20, "hex": "\
    00 14 00 10 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"}

    """

  private final class Directory {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-record-test-\(UUID().uuidString)",
      isDirectory: true
    )

    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    func write(_ text: String, as name: String) throws -> String {
      let file = url.appendingPathComponent(name)
      try Data(text.utf8).write(to: file)
      return file.path
    }

    func write(_ state: ControllerState, as name: String) throws -> String {
      let data = try JSONEncoder().encode(state)
      return try write(String(bytes: data, encoding: .utf8) ?? "", as: name)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  private func run(_ arguments: [String]) async -> CLIRun {
    await CLIRun.run(["record", "test"] + arguments)
  }

  @Test
  func aMatchingStateExitsZero() async throws {
    let directory = Directory()
    let packets = try directory.write(Self.capture, as: "capture.jsonl")
    let expect = try directory.write(ControllerState(pressed: [.faceSouth]), as: "expect.json")

    let human = await run([Self.identity, "--packets", packets, "--expect", expect])
    let json = await run([Self.identity, "--packets", packets, "--expect", expect, "--json"])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardError.contains(Self.identity))
    #expect(json.code == 0, "\(json.standardError)")
    let result = try json.json()
    #expect(result["matches"] as? Bool == true)
    #expect(result["inputReports"] as? Int == 1)
    #expect((result["differences"] as? [Any])?.isEmpty == true)
  }

  @Test
  func aMismatchExitsOneWithE2022AndNamesTheDifferingFields() async throws {
    let directory = Directory()
    let packets = try directory.write(Self.capture, as: "capture.jsonl")
    let expect = try directory.write(ControllerState(pressed: [.faceEast]), as: "expect.json")

    let human = await run([Self.identity, "--packets", packets, "--expect", expect])
    let json = await run([Self.identity, "--packets", packets, "--expect", expect, "--json"])

    #expect(human.code == 1)
    #expect(human.standardOutput.contains("pressed"))
    #expect(human.standardError.contains("E2022"))
    #expect(json.code == 1)
    let result = try json.json()
    #expect(result["matches"] as? Bool == false)
    let differences = try #require(result["differences"] as? [[String: Any]])
    #expect(differences.map { $0["field"] as? String } == ["pressed"])
    #expect(differences.first?["expected"] as? String == #"["face-east"]"#)
    #expect(differences.first?["actual"] as? String == #"["face-south"]"#)
  }

  @Test
  func anUnreadableCaptureExitsOneWithoutComparing() async throws {
    let directory = Directory()
    let expect = try directory.write(ControllerState(pressed: [.faceSouth]), as: "expect.json")
    let garbled = try directory.write("not json\n", as: "garbled.jsonl")
    let empty = try directory.write("", as: "empty.jsonl")
    let missing = directory.url.appendingPathComponent("missing.jsonl").path

    // A file that cannot be opened is a usage error (64), as for `record validate`.
    let absent = await run([Self.identity, "--packets", missing, "--expect", expect])
    #expect(absent.code == 64, "\(absent.standardError)")
    #expect(absent.standardOutput.isEmpty)

    for packets in [garbled, empty] {
      let result = await run([Self.identity, "--packets", packets, "--expect", expect])
      #expect(result.code == 1, "\(packets): \(result.standardError)")
      #expect(result.standardOutput.isEmpty)
      #expect(!result.standardError.contains("E2022"), "\(packets)")
    }
    let unreadableExpectation = try directory.write("{}", as: "bad-expect.json")
    let bad = await run([
      Self.identity, "--packets", try directory.write(Self.capture, as: "c.jsonl"),
      "--expect", unreadableExpectation,
    ])
    #expect(bad.code == 1)
    #expect(bad.standardError.contains("bad-expect.json"))
  }

  @Test
  func anUnknownRecordExitsOne() async throws {
    let directory = Directory()
    let packets = try directory.write(Self.capture, as: "capture.jsonl")
    let expect = try directory.write(ControllerState(), as: "expect.json")

    let result = await run(["0001:0001", "--packets", packets, "--expect", expect])

    #expect(result.code == 1)
    #expect(result.standardError.contains("0001:0001"))
  }
}
