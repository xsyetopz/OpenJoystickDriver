import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.removingTemporarySockets)
struct ConfigChangeCommandTests {
  /// A user record directory for one test, beside an empty `Packages` store.
  private final class Directory {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-config-change-\(UUID().uuidString)",
      isDirectory: true
    )

    var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
    var modelFile: URL { controllers.appendingPathComponent("2c22-2000.patch.plist") }
    var allFile: URL { controllers.appendingPathComponent("all.patch.plist") }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  /// A bundled `SonyDualShock4` record, a HID family that reads `stickDeadzone`.
  private static let model = "2C22:2000"

  private func run(_ arguments: [String], in directory: Directory) async -> CLIRun {
    await RecordStore.$directory.withValue(directory.controllers) {
      await CLIRun.run(["config"] + arguments)
    }
  }

  private func patch(_ file: URL) throws -> [String: Any] {
    try PropertyListFixture.dictionary(at: file)
  }

  /// The `stickDeadzone` row of `config show --json` as a value and a layer.
  private func shown(
    _ arguments: [String],
    in directory: Directory
  ) async throws -> (value: Double?, layer: String?) {
    let show = await run(["show", "--json"] + arguments, in: directory)
    #expect(show.code == 0, "\(show.standardError)")
    let values = try #require(try show.json()["values"] as? [[String: Any]])
    let row = values.first { $0["key"] as? String == "stickDeadzone" }
    return (row?["value"] as? Double, row?["layer"] as? String)
  }

  @Test
  func setWithControllerWritesThatModelsPatch() async throws {
    let directory = Directory()
    let result = await run(
      ["set", "stickDeadzone", "0.08", "--controller", Self.model, "--json"],
      in: directory
    )

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "ConfigChange")
    #expect(json["key"] as? String == "stickDeadzone")
    #expect(json["value"] as? Double == 0.08)
    #expect(json["controller"] as? String == Self.model)
    #expect(json["file"] as? String == directory.modelFile.path)
    #expect(json["created"] as? Bool == true)
    let written = try patch(directory.modelFile)
    #expect(written["kind"] as? String == "ControllerPatch")
    #expect(written["patch"] as? [String: [String: Double]] == ["tuning": ["stickDeadzone": 0.08]])
    let effective = try await shown(["--controller", Self.model], in: directory)
    #expect(effective.value == 0.08)
    #expect(effective.layer == "User")
    #expect(!FileManager.default.fileExists(atPath: directory.allFile.path))
  }

  @Test
  func setWithoutControllerWritesAllPatchJSON() async throws {
    let directory = Directory()
    let result = await run(["set", "stickDeadzone", "0.05", "--json"], in: directory)

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["controller"] == nil)
    #expect(json["file"] as? String == directory.allFile.path)
    let written = try patch(directory.allFile)
    #expect(written["selector"] as? [String: Bool] == ["all": true])
    #expect(written["patch"] as? [String: [String: Double]] == ["tuning": ["stickDeadzone": 0.05]])
    let effective = try await shown([], in: directory)
    #expect(effective.value == 0.05)
    #expect(effective.layer == "Global")
    #expect(!FileManager.default.fileExists(atPath: directory.modelFile.path))
  }

  @Test
  func setNamesPreviousValueAndPrintsHumanOutput() async throws {
    let directory = Directory()
    _ = await run(["set", "stickDeadzone", "0.1"], in: directory)
    let result = await run(["set", "stickDeadzone", "0.2", "--json"], in: directory)
    #expect(try result.json()["previous"] as? Double == 0.1)
    #expect(try result.json()["created"] as? Bool == false)

    let human = await run(["set", "stickDeadzone", "0.3"], in: directory)
    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardError.contains("stickDeadzone"))
    #expect(human.standardError.contains("0.3"))
    #expect(human.standardError.contains(directory.allFile.path))
  }

  @Test
  func unsetWithControllerRemovesKeyAndEmptyPatch() async throws {
    let directory = Directory()
    _ = await run(["set", "stickDeadzone", "0.08", "--controller", Self.model], in: directory)
    _ = await run(["set", "frameQueueCapacity", "32", "--controller", Self.model], in: directory)

    let first = await run(
      ["unset", "stickDeadzone", "--controller", Self.model, "--json"],
      in: directory
    )
    #expect(first.code == 0, "\(first.standardError)")
    #expect(try first.json()["value"] == nil)
    #expect(try first.json()["previous"] as? Double == 0.08)
    #expect(try first.json()["removesFile"] as? Bool == false)
    let kept = try patch(directory.modelFile)
    #expect(kept["patch"] as? [String: [String: Int]] == ["tuning": ["frameQueueCapacity": 32]])
    #expect(try await shown(["--controller", Self.model], in: directory).layer == "Driver")

    let last = await run(
      ["unset", "frameQueueCapacity", "--controller", Self.model, "--json"],
      in: directory
    )
    #expect(last.code == 0, "\(last.standardError)")
    #expect(try last.json()["removesFile"] as? Bool == true)
    #expect(!FileManager.default.fileExists(atPath: directory.modelFile.path))
  }

  @Test
  func unsetWithoutControllerRemovesKeyFromAllPatchJSON() async throws {
    let directory = Directory()
    _ = await run(["set", "stickDeadzone", "0.05"], in: directory)

    let result = await run(["unset", "stickDeadzone", "--json"], in: directory)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["controller"] == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.allFile.path))
    #expect(try await shown([], in: directory) == (nil, "Driver"))
  }

  @Test
  func globalOptionAfterNegativeValueStaysOption() async {
    let result = await run(["set", "stickDeadzone", "-0.5", "--json"], in: Directory())

    #expect(result.code == 64)
    #expect(!result.standardError.contains(CLILocalized.text("cli.config.set.valueCount")))
    #expect(result.standardError.contains("stickDeadzone"), "\(result.standardError)")
  }

  @Test(arguments: ["0", "1", "1.5", "-0.5"])
  func setRefusesValueOutOfRangeAndWritesNothing(_ value: String) async {
    let directory = Directory()
    for options in [["--controller", Self.model], []] {
      let result = await run(["set", "stickDeadzone", value] + options, in: directory)

      #expect(result.code == 64)
      #expect(result.standardError.contains(ErrorCode.usage.rawValue))
      #expect(result.standardError.contains("stickDeadzone"), "\(result.standardError)")
      #expect(!result.standardError.contains("Unknown option"))
    }
    #expect(!FileManager.default.fileExists(atPath: directory.modelFile.path))
    #expect(!FileManager.default.fileExists(atPath: directory.allFile.path))
  }

  @Test
  func setRefusesValueNotNumberAndUnknownKey() async {
    let directory = Directory()
    let text = await run(["set", "stickDeadzone", "wide"], in: directory)
    let unknown = await run(["set", "stickDeadzon", "0.1"], in: directory)

    #expect(text.code == 64 && unknown.code == 64)
    #expect(text.standardError.contains("'wide'"))
    #expect(unknown.standardError.contains("stickDeadzon"))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test(arguments: ["0x1p-3", "nan", "inf", "-inf", "1e-1", "1_0", " 0.1", "0.1 ", "+0.1", "."])
  func setAcceptsOnlyPlainDecimalNumber(_ value: String) async {
    let directory = Directory()
    let result = await run(["set", "stickDeadzone", value], in: directory)

    #expect(result.code == 64, "\(value)")
    #expect(result.standardError.contains(ErrorCode.usage.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test(arguments: ["0.15", ".15", "00.15", "0.150"])
  func setAcceptsPlainDecimalNumber(_ value: String) async throws {
    let directory = Directory()
    let result = await run(["set", "stickDeadzone", value, "--json"], in: directory)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["value"] as? Double == 0.15)
  }

  @Test
  func unsetRefusesKeyNotSet() async {
    let directory = Directory()
    for options in [["--controller", Self.model], []] {
      let result = await run(["unset", "stickDeadzone"] + options, in: directory)

      #expect(result.code == 1)
      #expect(result.standardError.contains(ErrorCode.notFound.rawValue))
    }
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func setRefusesModelWithoutRecord() async {
    let directory = Directory()
    let result = await run(
      ["set", "stickDeadzone", "0.1", "--controller", "1234:ABCD"],
      in: directory
    )

    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.notFound.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func setRefusesKeyModelsDriverDoesNotRead() async {
    let directory = Directory()
    let result = await run(
      ["set", "lizardResendTicks", "10", "--controller", Self.model],
      in: directory
    )

    #expect(result.code == 64)
    #expect(result.standardError.contains("lizardResendTicks"))
    #expect(!FileManager.default.fileExists(atPath: directory.modelFile.path))
  }
}
