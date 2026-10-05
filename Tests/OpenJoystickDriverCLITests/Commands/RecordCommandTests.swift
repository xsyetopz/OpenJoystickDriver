import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

struct RecordCommandTests {
  /// A patch of the bundled `xbox.gip` record `366C:0005`.
  private static let patch = Data(
    """
    {"$schema": "\(ControllerRecordSet.overrideSchemaID)", "operation": "patch",
     "vendorID": 13932, "productID": 5, "set": {"usb": {"postHandshakeSettleMs": 5}}}
    """.utf8
  )

  /// A user directory that exists for one test.
  private final class Directory {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-record-\(UUID().uuidString)",
      isDirectory: true
    )

    var fileNames: [String] {
      ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
    }

    func write(_ data: Data, as name: String) throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      try data.write(to: url.appendingPathComponent(name))
    }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  private func run(
    _ arguments: [String],
    in directory: Directory,
    stdin: Data = Data()
  ) async -> CLIRun {
    await RecordStore.$directory.withValue(directory.url) {
      await RecordStore.$standardInput.withValue(
        { stdin },
        operation: { await CLIRun.run(["record"] + arguments) }
      )
    }
  }

  @Test
  func validateReportsTheRecordAndItsTransport() async throws {
    let directory = Directory()

    let json = await run(["validate", "-", "--json"], in: directory, stdin: Self.patch)
    let human = await run(["validate", "-"], in: directory, stdin: Self.patch)

    #expect(json.code == 0, "\(json.standardError)")
    let result = try json.json()
    #expect(result["valid"] as? Bool == true)
    #expect(result["operation"] as? String == "patch")
    #expect(result["identity"] as? String == "366C:0005")
    #expect(result["fileName"] as? String == "366c-0005.json")
    #expect(result["transport"] as? String == "usb")
    #expect(result["usbExtension"] as? String == "does-not-claim")
    #expect(human.standardOutput.contains("366C:0005"))
    #expect(directory.fileNames.isEmpty)
  }

  @Test
  func anInvalidRecordExitsOneAndNamesTheProblem() async throws {
    let directory = Directory()
    let invalid = Data(#"{"operation": "patch"}"#.utf8)

    let json = await run(["validate", "-", "--json"], in: directory, stdin: invalid)
    let install = await run(["install", "-"], in: directory, stdin: invalid)
    let missing = await run(["validate", "/nonexistent-\(UUID().uuidString).json"], in: directory)

    #expect(json.code == 1)
    #expect(try json.json()["valid"] as? Bool == false)
    #expect((try json.json()["problem"] as? String)?.contains("$schema") == true)
    #expect(json.standardError.hasPrefix("error[E2011]: "))
    #expect(json.standardError.contains("$schema"))
    #expect(install.code == 1)
    #expect(directory.fileNames.isEmpty)
    #expect(missing.code == 64)
  }

  @Test
  func installWritesTheFileThatListAndShowReport() async throws {
    let directory = Directory()

    let install = await run(["install", "-", "--json"], in: directory, stdin: Self.patch)
    let again = await run(["install", "-", "--json"], in: directory, stdin: Self.patch)
    let list = await run(["list", "--plain"], in: directory)
    let show = await run(["show", "366c:0005", "--json"], in: directory)
    let plainShow = await run(["show", "366C:0005", "--plain"], in: directory)

    #expect(install.code == 0, "\(install.standardError)")
    #expect(try install.json()["replaced"] as? Bool == false)
    #expect(try again.json()["replaced"] as? Bool == true)
    #expect(directory.fileNames == ["366c-0005.json"])
    #expect(
      try Data(contentsOf: directory.url.appendingPathComponent("366c-0005.json")) == Self.patch
    )
    let row = try #require(
      list.standardOutput.split(separator: "\n").first { $0.hasPrefix("366C:0005\t") }
    )
    #expect(row.hasPrefix("366C:0005\txbox.gip\tuser\t"))
    #expect(list.standardOutput.contains("\tbundled\t"))
    let shown = try show.json()
    #expect(shown["layer"] as? String == "user")
    #expect(shown["fields"] as? [String: String] == ["protocol": "bundled", "usb": "user"])
    let record = try #require(shown["record"] as? [String: Any])
    #expect((record["usb"] as? [String: Int])?["postHandshakeSettleMs"] == 5)
    #expect(plainShow.standardOutput == "protocol\tbundled\nusb\tuser\n")
  }

  @Test
  func listNamesSkippedFilesAndBundledListsTheCatalogAlone() async throws {
    let directory = Directory()
    try directory.write(Self.patch, as: "wrong.json")

    let list = await run(["list", "--json"], in: directory)
    let bundled = await run(["list", "--bundled", "--json"], in: directory)

    #expect(list.code == 0)
    let skipped = try #require(try list.json()["skipped"] as? [[String: String]])
    #expect(skipped.count == 1)
    #expect(skipped.first?["problem"]?.contains("366c-0005.json") == true)
    #expect(list.standardError.contains("wrong.json"))
    let records = try #require(try bundled.json()["records"] as? [[String: Any]])
    #expect(records.count == ControllerRecordSet.bundled.records.count)
    #expect(records.allSatisfy { $0["layer"] as? String == "bundled" })
    #expect(try bundled.json()["skipped"] == nil)
  }

  @Test
  func showAnUnknownModelExitsOne() async {
    let result = await run(["show", "1234:ABCD"], in: Directory())
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2012]: "))
    #expect(result.standardError.contains("1234:ABCD"))
  }

  @Test
  func removeNeedsForceWithoutATerminalAndHonorsDryRun() async throws {
    let directory = Directory()
    try directory.write(Self.patch, as: "366c-0005.json")

    let dryRun = await run(["remove", "366C:0005", "--dry-run", "--json"], in: directory)
    let unforced = await run(["remove", "366C:0005", "--no-input"], in: directory)
    #expect(dryRun.code == 0)
    #expect(try dryRun.json()["dryRun"] as? Bool == true)
    #expect(unforced.code == 64)
    #expect(directory.fileNames == ["366c-0005.json"])

    let removed = await run(["remove", "366C:0005", "--force"], in: directory)
    let absent = await run(["remove", "366C:0005", "--force"], in: directory)
    #expect(removed.code == 0, "\(removed.standardError)")
    #expect(directory.fileNames.isEmpty)
    #expect(absent.code == 1)
  }

  /// A descriptor reader that finds none.
  private static let noDescriptor: @Sendable (Int, Int) -> [UInt8]? = { _, _ in nil }

  @Test
  func draftPrintsARecordFromTheCapturedReports() async throws {
    let reads = Counter()
    let packets = """
      [{"direction":"rx","hex":"00 01 02","length":3,"timestamp":1},
       {"direction":"tx","hex":"00 00 00","length":3,"timestamp":2},
       {"direction":"rx","hex":"00 01 05","length":3,"timestamp":3}]
      """
    let service = try FakeService(
      devices: [
        ApplicationServiceDeviceDescription.fixture(
          id: "pad-1",
          vendorID: 0x1234,
          productID: 0x5678
        )
      ]
    ) { method, _ in
      guard method == .getPacketLog else { return nil }
      return encoded(Data((reads.next() == 0 ? "[]" : packets).utf8))
    }
    let result = await RecordDraftCommand.$descriptor.withValue(Self.noDescriptor) {
      await service.run(["record", "draft", "pad-1", "--duration", "0.3", "--json"])
    }
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["operation"] as? String == "add")
    #expect(json["family"] as? String == "hid.descriptor")
    #expect(json["capturedReports"] as? Int == 2)
    #expect(json["report"] as? [String: Int] == ["length": 3])
    #expect(json["changedBytes"] as? [[String: Int]] == [["byte": 2, "minimum": 2, "maximum": 5]])
    let record = try #require(json["record"] as? [String: Any])
    #expect(record["operation"] as? String == "add")
  }

  /// A bundled model whose descriptor maps nothing keeps its bundled family.
  @Test
  func draftOfABundledModelWithoutALayoutExitsOne() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ]) { method, _ in
      method == .getPacketLog ? encoded(Data("[]".utf8)) : nil
    }
    let result = await RecordDraftCommand.$descriptor.withValue(Self.noDescriptor) {
      await service.run(["record", "draft", "pad-1", "--duration", "0.2"])
    }
    #expect(result.code == 1)
    #expect(result.standardError.contains("ojd record show 045E:028E"))
  }
}
