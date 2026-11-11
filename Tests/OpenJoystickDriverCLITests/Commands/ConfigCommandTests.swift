import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.removingTemporarySockets)
struct ConfigCommandTests {
  /// A directory that holds `Controllers/` and its `all.patch.plist` for one test.
  private final class Root {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-config-\(UUID().uuidString)",
      isDirectory: true
    )

    func writeDefaults(_ tuning: String) throws {
      let controllers = url.appendingPathComponent("Controllers", isDirectory: true)
      try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
      let json =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"ControllerPatch","#
        + #""selector":{"all":true},"patch":{"tuning":\#(tuning)}}"#
      try PropertyListFixture.data(json: json).write(to: ControllerDefaults.file(in: controllers))
    }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  private func run(_ arguments: [String], in root: Root) async -> CLIRun {
    await RecordStore.$directory.withValue(root.url.appendingPathComponent("Controllers")) {
      await CLIRun.run(["config"] + arguments)
    }
  }

  private func bareModel() throws -> ControllerModelID {
    try #require(
      ControllerRecordSet.bundled.records.values.first {
        $0.family == "XboxGIP" && $0.tuning.stickDeadzone == nil
      }
    ).model
  }

  private func bareIdentity() throws -> String {
    let model = try bareModel()
    return deviceIdentity(vendorID: Int(model.vendorID), productID: Int(model.productID))
  }

  private func values(_ run: CLIRun) throws -> [String: [String: Any]] {
    let list = try #require(try run.json()["values"] as? [[String: Any]])
    return Dictionary(uniqueKeysWithValues: list.map { ($0["key"] as? String ?? "", $0) })
  }

  @Test
  func showListsEveryKeyAsADriverDefaultWithoutADefaultsFile() async throws {
    let run = await run(["show", "--json"], in: Root())

    #expect(run.code == 0, "\(run.standardError)")
    let values = try values(run)
    #expect(values.count == ControllerTuning.Key.allCases.count)
    #expect(values.values.allSatisfy { $0["layer"] as? String == "Driver" && $0["value"] == nil })
  }

  @Test
  func showReportsTheGlobalLayerForAKeyDefaultsJSONSets() async throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)

    let run = await run(["show", "--json"], in: root)

    #expect(run.code == 0, "\(run.standardError)")
    let stick = try #require(try values(run)["stickDeadzone"])
    #expect(stick["value"] as? Double == 0.2)
    #expect(stick["layer"] as? String == "Global")
  }

  @Test
  func showForAControllerReportsTheLayerOfItsEffectiveValue() async throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)
    let identity = try bareIdentity()

    let run = await run(["show", "--controller", identity, "--json"], in: root)

    #expect(run.code == 0, "\(run.standardError)")
    #expect(try run.json()["controller"] as? String == identity)
    #expect(try values(run)["stickDeadzone"]?["layer"] as? String == "Global")
    #expect(try values(run)["inputLivenessTimeoutMs"]?["layer"] as? String == "Driver")
  }

  @Test
  func showPrintsEachValueWithItsLayerInHumanOutput() async throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)

    let run = await run(["show"], in: root)

    #expect(run.code == 0, "\(run.standardError)")
    #expect(run.standardOutput.contains("stickDeadzone"))
    #expect(run.standardOutput.contains("0.2  (global)"))
    #expect(run.standardOutput.contains("(driver)"))
  }

  @Test
  func showNamesTheDriverDefaultOnlyForAKeyTheDriverGivesAValue() async throws {
    let run = await run(["show"], in: Root())

    #expect(run.code == 0, "\(run.standardError)")
    let lines = run.standardOutput.split(separator: "\n").map(String.init)
    let deadzone = try #require(lines.first { $0.hasPrefix("stickDeadzone ") })
    let capacity = try #require(lines.first { $0.hasPrefix("frameQueueCapacity ") })
    #expect(deadzone.contains(CLILocalized.text("status.notSet")))
    #expect(capacity.contains(CLILocalized.text("status.driverDefault")))
  }

  @Test
  func showForAControllerAddsTheActiveProfilesStickDeadzonesInTheProfileLayer() async throws {
    let root = Root()
    let identity = try bareIdentity()
    let model = try bareModel()
    let profile = RemappingProfile(
      id: UUID(),
      name: "Aim",
      device: RemappingDeviceScope(vendorID: model.vendorID, productID: model.productID),
      applicationScope: .global,
      stickMappings: [
        RemappingStickMapping(source: .left),
        RemappingStickMapping(source: .right, tuning: RemappingStickTuning(innerDeadzone: 0.25)),
      ],
      bindings: []
    )
    let library = FakeProfileLibrary([profile], active: [profile.id])
    let service = try FakeService(devices: [], respond: library.respond)

    let run = await RecordStore.$directory.withValue(root.url.appendingPathComponent("Controllers"))
    {
      await service.run(["config", "show", "--controller", identity, "--json"])
    }

    #expect(run.code == 0, "\(run.standardError)")
    #expect(try run.json()["profile"] as? String == "Aim")
    let values = try values(run)
    #expect(values["stickMappings.0.tuning.innerDeadzone"]?["value"] as? Double == 0.1)
    #expect(values["stickMappings.1.tuning.innerDeadzone"]?["value"] as? Double == 0.25)
    #expect(values["stickMappings.1.tuning.innerDeadzone"]?["layer"] as? String == "Profile")
    #expect(values["stickDeadzone"]?["layer"] as? String == "Driver")
  }

  @Test
  func showForAControllerWithoutARunningServiceHasNoProfileRows() async throws {
    let identity = try bareIdentity()

    let run = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await self.run(["show", "--controller", identity, "--json"], in: Root())
    }

    #expect(run.code == 0, "\(run.standardError)")
    #expect(try run.json()["profile"] == nil)
    #expect(try values(run).count == ControllerTuning.Key.allCases.count)
  }

  private func record(family: String) throws -> ControllerRecord {
    try #require(ControllerRecordSet.bundled.records.values.first { $0.family == family })
  }

  private func connected(_ record: ControllerRecord) -> ApplicationServiceDeviceDescription {
    .fixture(
      id: "pad-1",
      vendorID: record.model.vendorID,
      productID: record.model.productID
    )
  }

  /// `config show --json` with `defaults` written and `devices` connected to a fake service.
  private func runWithService(
    defaults: String,
    devices: [ApplicationServiceDeviceDescription]
  ) async throws -> CLIRun {
    let root = Root()
    try root.writeDefaults(defaults)
    let service = try FakeService(devices: devices)
    return await RecordStore.$directory.withValue(root.url.appendingPathComponent("Controllers")) {
      await service.run(["config", "show", "--json"])
    }
  }

  @Test
  func showListsTheFamiliesThatReadEachKeyWithoutAController() async throws {
    let run = await run(["show", "--json"], in: Root())

    #expect(run.code == 0, "\(run.standardError)")
    let values = try values(run)
    let liveness = values["inputLivenessTimeoutMs"]?["families"] as? [String]
    #expect(liveness == ["SonyDualShock4", "SonySixaxis"])
    let deadzone = try #require(values["stickDeadzone"]?["families"] as? [String])
    #expect(deadzone.contains("XboxGIP") && deadzone.contains("SonyDualShock4"))
    let recovery = try #require(values["hidStartupRecoveryRounds"]?["families"] as? [String])
    #expect(recovery == ["NintendoSwitch1"])
  }

  @Test
  func showForAControllerListsNoFamilies() async throws {
    let run = await run(["show", "--controller", try bareIdentity(), "--json"], in: Root())

    #expect(run.code == 0, "\(run.standardError)")
    #expect(try values(run).values.allSatisfy { $0["families"] == nil })
  }

  @Test
  func showPrintsTheFamiliesNextToEachKeyInHumanOutput() async throws {
    let run = await run(["show"], in: Root())

    #expect(run.code == 0, "\(run.standardError)")
    let line = try #require(
      run.standardOutput.split(separator: "\n").first { $0.hasPrefix("inputLivenessTimeoutMs") }
    )
    #expect(line.hasSuffix("read by: SonyDualShock4, SonySixaxis"))
  }

  @Test
  func showWarnsWhenNoConnectedControllerReadsAKeyDefaultsJSONSets() async throws {
    let gip = try record(family: "XboxGIP")

    let run = try await runWithService(
      defaults: #"{"inputLivenessTimeoutMs":900,"stickDeadzone":0.2}"#,
      devices: [connected(gip)]
    )

    #expect(run.code == 0, "\(run.standardError)")
    #expect(run.standardError.contains("inputLivenessTimeoutMs"))
    #expect(run.standardError.contains("SonyDualShock4"))
    #expect(!run.standardError.contains("stickDeadzone"))
    #expect(try values(run)["inputLivenessTimeoutMs"]?["value"] as? Double == 900)
  }

  @Test
  func showDoesNotWarnWhenAConnectedControllerReadsTheKey() async throws {
    let run = try await runWithService(
      defaults: #"{"inputLivenessTimeoutMs":900}"#,
      devices: [connected(try record(family: "SonyDualShock4"))]
    )

    #expect(run.code == 0, "\(run.standardError)")
    #expect(run.standardError.isEmpty)
  }

  @Test
  func showNotesASkippedCheckWithoutAConnectedController() async throws {
    let run = try await runWithService(defaults: #"{"inputLivenessTimeoutMs":900}"#, devices: [])

    #expect(run.code == 0, "\(run.standardError)")
    #expect(
      run.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        == CLILocalized.text("cli.config.show.unreadSkippedNoController")
    )
    #expect(try values(run)["inputLivenessTimeoutMs"]?["value"] as? Double == 900)
  }

  @Test
  func showNotesASkippedCheckWithoutARunningService() async throws {
    let root = Root()
    try root.writeDefaults(#"{"inputLivenessTimeoutMs":900}"#)

    let run = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await self.run(["show", "--json"], in: root)
    }

    #expect(run.code == 0, "\(run.standardError)")
    #expect(
      run.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        == CLILocalized.text("cli.config.show.unreadSkippedNoService")
    )
  }

  @Test
  func showStaysQuietWhenDefaultsJSONSetsNoKey() async throws {
    let root = Root()
    try root.writeDefaults("{}")

    let run = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await self.run(["show", "--json"], in: root)
    }

    #expect(run.code == 0, "\(run.standardError)")
    #expect(run.standardError.isEmpty)
  }

  @Test
  func showFailsForAControllerWithoutARecord() async {
    let run = await run(["show", "--controller", "FFFF:FFFF"], in: Root())

    #expect(run.code != 0)
  }
}
