import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct RecordCommandTests {
  /// A patch of the bundled `XboxGIP` record `366C:0005`.
  private static let patch = PropertyListFixture.bytes(
    json: """
      {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
       "selector": {"vendorID": 13932, "productID": 5},
       "patch": {"tuning": {"stickDeadzone": 0.08}}}
      """
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
    #expect(result["operation"] as? String == "Patch")
    #expect(result["identity"] as? String == "366C:0005")
    #expect(result["fileName"] as? String == "366c-0005.patch.plist")
    #expect(result["transport"] as? String == "USB")
    #expect(result["transportClaim"] as? String == "Unclaimed")
    #expect(human.standardOutput.contains("366C:0005"))
    #expect(directory.fileNames.isEmpty)
  }

  @Test
  func anInvalidRecordExitsOneAndNamesTheProblem() async throws {
    let directory = Directory()
    let invalid = PropertyListFixture.bytes(json: #"{"operation": "patch"}"#)

    let json = await run(["validate", "-", "--json"], in: directory, stdin: invalid)
    let install = await run(["install", "-"], in: directory, stdin: invalid)
    let missing = await run(["validate", "/nonexistent-\(UUID().uuidString).json"], in: directory)

    #expect(json.code == 1)
    #expect(try json.json()["valid"] as? Bool == false)
    #expect((try json.json()["problem"] as? String)?.contains("apiVersion") == true)
    #expect(json.standardError.hasPrefix("error[E5001]: "))
    #expect(json.standardError.contains("no apiVersion found"))
    #expect(install.code == 1)
    #expect(directory.fileNames.isEmpty)
    #expect(missing.code == 64)
  }

  @Test
  func aRecordThatBreaksARuleReportsE5007() async throws {
    let directory = Directory()
    let invalid = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
         "selector": {"all": false}, "patch": {"tuning": {"stickDeadzone": 0.08}}}
        """
    )

    let result = await run(["validate", "-"], in: directory, stdin: invalid)

    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E5007]: "))
  }

  @Test
  func installWritesTheFileThatListAndShowReport() async throws {
    let directory = Directory()

    let install = await run(["install", "-", "--json"], in: directory, stdin: Self.patch)
    let again = await run(["install", "-", "--force", "--json"], in: directory, stdin: Self.patch)
    let list = await run(["list", "--plain"], in: directory)
    let show = await run(["show", "366c:0005", "--json"], in: directory)
    let plainShow = await run(["show", "366C:0005", "--plain"], in: directory)
    let humanShow = await run(["show", "366C:0005"], in: directory)

    #expect(install.code == 0, "\(install.standardError)")
    #expect(try install.json()["replaced"] as? Bool == false)
    #expect(try again.json()["replaced"] as? Bool == true)
    #expect(directory.fileNames == ["366c-0005.patch.plist"])
    #expect(
      try Data(contentsOf: directory.url.appendingPathComponent("366c-0005.patch.plist"))
        == Self.patch
    )
    let row = try #require(
      list.standardOutput.split(separator: "\n").first { $0.hasPrefix("366C:0005\t") }
    )
    #expect(row.hasPrefix("366C:0005\txbox-gip\tuser\t"))
    #expect(list.standardOutput.contains("\tbundled\t"))
    let shown = try show.json()
    #expect(shown["layer"] as? String == "User")
    #expect(shown["fields"] as? [String: String] == ["modes": "Bundled", "tuning": "User"])
    let record = try #require(shown["record"] as? [String: Any])
    #expect((record["tuning"] as? [String: Double])?["stickDeadzone"] == 0.08)
    #expect(plainShow.standardOutput == "modes\tbundled\ntuning\tuser\n")
    let document = try #require(
      ControllerRecordSet.load(userDirectory: directory.url).records[
        ControllerModelID(vendorID: 0x366C, productID: 0x0005)
      ]?.text
    )
    #expect(humanShow.standardOutput.hasSuffix("\n\n" + document))
    #expect(humanShow.standardOutput.hasSuffix("  }\n}\n"))
  }

  @Test
  func listNamesSkippedFilesAndBundledListsTheCatalogAlone() async throws {
    let directory = Directory()
    try directory.write(Self.patch, as: "wrong.plist")

    let list = await run(["list", "--json"], in: directory)
    let bundled = await run(["list", "--bundled", "--json"], in: directory)

    #expect(list.code == 0)
    let metadata = try #require(try list.json()["metadata"] as? [String: Any])
    #expect(metadata.isEmpty)
    #expect(list.standardError.contains("wrong.plist"))
    #expect(list.standardError.contains("366c-0005.patch.plist"))
    let records = try #require(try bundled.json()["items"] as? [[String: Any]])
    #expect(records.count == ControllerRecordSet.bundled.records.count)
    #expect(records.allSatisfy { $0["layer"] as? String == "Bundled" })
    #expect((try bundled.json()["metadata"] as? [String: Any])?.isEmpty == true)
  }

  @Test
  func showAnUnknownModelExitsOne() async {
    let result = await run(["show", "1234:ABCD"], in: Directory())
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2012]: "))
    #expect(result.standardError.contains("1234:ABCD"))
  }

  @Test
  func validateAndShowNoteThatASwitch2RecordWithoutBluetoothLEIsUSBOnly() async throws {
    let directory = Directory()
    let switch2 = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
         "vendorID": 1406, "productID": 8447,
         "modes": [{"id": "default", "protocol": {"family": "NintendoSwitch2"}}]}
        """
    )
    try directory.write(switch2, as: "057e-20ff.plist")
    let note = CLILocalized.text("cli.record.group.usbOnlySwitch2")

    let validate = await run(["validate", "-"], in: directory, stdin: switch2)
    let show = await run(["show", "057E:20FF"], in: directory)
    let bundled = await run(["show", "057E:2066"], in: directory)

    #expect(validate.code == 0, "\(validate.standardError)")
    #expect(validate.standardOutput.contains(note))
    #expect(show.code == 0, "\(show.standardError)")
    #expect(show.standardOutput.contains(note))
    #expect(bundled.code == 0, "\(bundled.standardError)")
    #expect(!bundled.standardOutput.contains(note))
  }

  @Test
  func installNeedsForceToReplaceWithoutATerminalAndHonorsDryRun() async throws {
    let directory = Directory()
    let installed = PropertyListFixture.bytes(json: "{}")
    let dryRun = await run(
      ["install", "-", "--dry-run", "--json"],
      in: directory,
      stdin: Self.patch
    )
    #expect(dryRun.code == 0, "\(dryRun.standardError)")
    #expect(try dryRun.json()["dryRun"] as? Bool == true)
    #expect(try dryRun.json()["replaced"] as? Bool == false)
    #expect(directory.fileNames.isEmpty)

    try directory.write(installed, as: "366c-0005.patch.plist")
    let unforced = await run(["install", "-", "--no-input"], in: directory, stdin: Self.patch)
    let replacing = await run(["install", "-", "-n", "--json"], in: directory, stdin: Self.patch)
    let file = directory.url.appendingPathComponent("366c-0005.patch.plist")
    #expect(unforced.code == 64)
    #expect(try replacing.json()["replaced"] as? Bool == true)
    #expect(try Data(contentsOf: file) == installed)

    let forced = await run(["install", "-", "--force"], in: directory, stdin: Self.patch)
    #expect(forced.code == 0, "\(forced.standardError)")
    #expect(try Data(contentsOf: file) == Self.patch)
  }

  @Test
  func removeNeedsForceWithoutATerminalAndHonorsDryRun() async throws {
    let directory = Directory()
    try directory.write(Self.patch, as: "366c-0005.patch.plist")

    let dryRun = await run(["remove", "366C:0005", "--dry-run", "--json"], in: directory)
    let unforced = await run(["remove", "366C:0005", "--no-input"], in: directory)
    #expect(dryRun.code == 0)
    #expect(try dryRun.details()["dryRun"] as? Bool == true)
    #expect(unforced.code == 64)
    #expect(directory.fileNames == ["366c-0005.patch.plist"])

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
      [{"direction":"Rx","hex":"00 01 02","length":3,"timestamp":1},
       {"direction":"Tx","hex":"00 00 00","length":3,"timestamp":2},
       {"direction":"Rx","hex":"00 01 05","length":3,"timestamp":3}]
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
      await service.run(["record", "draft", token("pad-1"), "--duration", "0.3", "--json"])
    }
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["operation"] as? String == "Add")
    #expect(json["family"] as? String == "HIDDescriptor")
    #expect(json["capturedReports"] as? Int == 2)
    #expect(json["report"] as? [String: Int] == ["length": 3])
    #expect(json["changedBytes"] as? [[String: Int]] == [["byte": 2, "minimum": 2, "maximum": 5]])
    let record = try #require(json["record"] as? [String: Any])
    #expect(record["kind"] as? String == "Controller")
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
      await service.run(["record", "draft", token("pad-1"), "--duration", "0.2"])
    }
    #expect(result.code == 1)
    #expect(result.standardError.contains("ojd record show 045E:028E"))
  }

  /// Runs `record draft --from-sdl` for a controller of the model, whose pad is `pad`.
  private func draftFromSDL(
    vendorID: UInt16,
    productID: UInt16,
    pad: PhysicalDevice?
  ) async throws
    -> CLIRun
  {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(
        id: "pad-1",
        vendorID: vendorID,
        productID: productID
      )
    ])
    let read: @Sendable (Int, Int) -> PhysicalDevice? = { _, _ in pad }
    return await RecordDraftCommand.$physicalDevice.withValue(read) {
      await service.run(["record", "draft", token("pad-1"), "--from-sdl"])
    }
  }

  /// A pad of the model with a valid descriptor and no input elements.
  private func pad(vendorID: UInt16, productID: UInt16, version: UInt16 = 0x0100) -> PhysicalDevice
  {
    PhysicalDevice(
      vendorID: vendorID,
      productID: productID,
      deviceRelease: version,
      interfaces: [
        PhysicalInterfaceSignature(
          hostTransport: .usb,
          accessBackend: .hid,
          hidLayout: HIDLayoutSummary(
            reportDescriptor: Data(GamepadHIDDescriptor.descriptor),
            elements: []
          )
        )
      ]
    )
  }

  @Test
  func fromSDLWithNoPadReadableExitsOneWithE2013() async throws {
    let result = try await draftFromSDL(vendorID: 0x1234, productID: 0x5678, pad: nil)
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2013]: "))
  }

  @Test
  func fromSDLOfAPadWithNoDatabaseLineExitsOneWithE2012() async throws {
    let result = try await draftFromSDL(
      vendorID: 0x1234,
      productID: 0x5678,
      pad: pad(vendorID: 0x1234, productID: 0x5678)
    )
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2012]: "))
  }

  @Test
  func fromSDLOfALineThatDoesNotConvertExitsOneWithE5008() async throws {
    let result = try await draftFromSDL(
      vendorID: 0x358A,
      productID: 0x0201,
      pad: pad(vendorID: 0x358A, productID: 0x0201)
    )
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E5008]: "))
  }

  @Test
  func fromSDLOfABundledModelExitsOneWithE2013() async throws {
    let result = try await draftFromSDL(
      vendorID: 0x045E,
      productID: 0x028E,
      pad: pad(vendorID: 0x045E, productID: 0x028E)
    )
    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2013]: "))
  }

  /// `record show --json` ends in one newline and keeps the members of the envelope sorted by name.
  @Test
  func showJSONSortsTheEnvelopeAndEndsInOneNewline() async throws {
    let directory = Directory()
    let record = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "Controller",
         "vendorID": 4617, "productID": 2,
         "modes": [{"id": "default", "protocol": {"family": "XboxGIP"}}]}
        """
    )
    try directory.write(record, as: "1209-0002.plist")
    let json = await run(["show", "1209:0002", "--json"], in: directory)

    #expect(json.code == 0, "\(json.standardError)")
    let output = json.standardOutput
    #expect(output.hasPrefix("{\n  \"apiVersion\": "))
    #expect(output.hasSuffix("}\n"))
    #expect(!output.hasSuffix("\n\n"))
    let names = ["apiVersion", "family", "identity", "kind", "layer", "record", "transport"]
    let positions = try names.map { try #require(output.range(of: "\n  \"\($0)\"")).lowerBound }
    #expect(positions == positions.sorted())
  }

  /// No record field takes an integer of 25 digits, so the command refuses it and does not
  /// round it to a `Double` and accept it.
  @Test
  func anIntegerBeyond64BitsInATuningValueIsRefused() async throws {
    let directory = Directory()
    let patch = PropertyListFixture.bytes(
      json: """
        {"apiVersion": "\(OpenJoystickDriverAPI.version)", "kind": "ControllerPatch",
         "selector": {"vendorID": 13932, "productID": 5},
         "patch": {"tuning": {"usbTransferTimeoutMs": 1234567890123456789012345}}}
        """
    )

    let result = await run(["validate", "-", "--json"], in: directory, stdin: patch)

    #expect(result.code == 1, "\(result.standardOutput)")
    #expect(directory.fileNames.isEmpty)
  }
}
