import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ConfigCommandTests {
  /// A directory that holds `Controllers/` and `Defaults.json` for one test.
  private final class Root {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-config-\(UUID().uuidString)",
      isDirectory: true
    )

    func writeDefaults(_ tuning: String) throws {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      let json = #"{"$schema":"\#(ControllerDefaults.schemaID)","tuning":\#(tuning)}"#
      try Data(json.utf8).write(to: url.appendingPathComponent("Defaults.json"))
    }

    deinit { try? FileManager.default.removeItem(at: url) }
  }

  private func run(_ arguments: [String], in root: Root) async -> CLIRun {
    await RecordStore.$directory.withValue(root.url.appendingPathComponent("Controllers")) {
      await CLIRun.run(["config"] + arguments)
    }
  }

  private func bareIdentity() throws -> String {
    let record = try #require(
      ControllerRecordSet.bundled.records.values.first {
        $0.family == "xbox.gip" && $0.tuning.stickDeadzone == nil
      }
    )
    return deviceIdentity(
      vendorID: Int(record.identity.vendorID),
      productID: Int(record.identity.productID)
    )
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
    #expect(values.values.allSatisfy { $0["layer"] as? String == "driver" && $0["value"] == nil })
  }

  @Test
  func showReportsTheGlobalLayerForAKeyDefaultsJSONSets() async throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)

    let run = await run(["show", "--json"], in: root)

    #expect(run.code == 0, "\(run.standardError)")
    let stick = try #require(try values(run)["stickDeadzone"])
    #expect(stick["value"] as? Double == 0.2)
    #expect(stick["layer"] as? String == "global")
  }

  @Test
  func showForAControllerReportsTheLayerOfItsEffectiveValue() async throws {
    let root = Root()
    try root.writeDefaults(#"{"stickDeadzone":0.2}"#)
    let identity = try bareIdentity()

    let run = await run(["show", "--controller", identity, "--json"], in: root)

    #expect(run.code == 0, "\(run.standardError)")
    #expect(try run.json()["controller"] as? String == identity)
    #expect(try values(run)["stickDeadzone"]?["layer"] as? String == "global")
    #expect(try values(run)["inputLivenessTimeoutMs"]?["layer"] as? String == "driver")
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
  func showForAControllerAddsTheActiveProfilesStickDeadzonesInTheProfileLayer() async throws {
    let root = Root()
    let identity = try bareIdentity()
    let (vendorID, productID) = try #require(ControllerSelection.model(identity))
    let profile = RemappingProfile(
      id: UUID(),
      name: "Aim",
      device: RemappingDeviceScope(vendorID: vendorID, productID: productID),
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
    #expect(values["stickMappings.1.tuning.innerDeadzone"]?["layer"] as? String == "profile")
    #expect(values["stickDeadzone"]?["layer"] as? String == "driver")
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

  @Test
  func showFailsForAControllerWithoutARecord() async {
    let run = await run(["show", "--controller", "FFFF:FFFF"], in: Root())

    #expect(run.code != 0)
  }
}
