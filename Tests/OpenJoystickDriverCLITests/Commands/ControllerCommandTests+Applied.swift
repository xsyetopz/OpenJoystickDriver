import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `controller show` reports what is applied: the effective tuning and who owns the output.
@Suite(.serialized)
struct ControllerShowAppliedTests {
  private static let tuning = ControllerTuning(
    stickDeadzone: 0.2,
    inputLivenessTimeoutMilliseconds: 1500,
    hidStartupRecoveryRounds: 3
  )

  @Test
  func showReportsEffectiveTuningInJSONPlainAndHumanOutput() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1", tuning: Self.tuning)
    ])

    let json = await service.run(["controller", "show", token("pad-1"), "--json"])
    let plain = await service.run(["controller", "show", token("pad-1"), "--plain"])
    let human = await service.run(["controller", "show", token("pad-1")])

    #expect(json.code == 0, "\(json.standardError)")
    let controller = try json.json()
    let tuning = try #require(controller["tuning"] as? [String: Any])
    #expect(tuning["stickDeadzone"] as? Double == 0.2)
    #expect(tuning["inputLivenessTimeoutMs"] as? Int == 1500)
    #expect(tuning["hidStartupRecoveryRounds"] as? Int == 3)
    #expect(tuning["hidStartupIntervalMs"] == nil)
    #expect(
      plain.standardOutput.contains(
        "\ntuning\tstickDeadzone=0.2\tinputLivenessTimeoutMs=1500\thidStartupRecoveryRounds=3\n"
      )
    )
    #expect(
      human.standardOutput.contains(
        "stickDeadzone=0.2, inputLivenessTimeoutMs=1500, hidStartupRecoveryRounds=3"
      )
    )
  }

  @Test
  func showLeavesOutTuningWhenRecordSetsNone() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])

    let json = await service.run(["controller", "show", token("pad-1"), "--json"])
    let plain = await service.run(["controller", "show", token("pad-1"), "--plain"])

    let controller = try json.json()
    #expect(controller["tuning"] == nil)
    #expect(!plain.standardOutput.contains("\ntuning\t"))
  }

  @Test
  func showNamesMacOSAsOutputOwnerNextToNarrowedCapabilities() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1", physicalOutputOwner: .system)
    ])

    let json = await service.run(["controller", "show", token("pad-1"), "--json"])
    let plain = await service.run(["controller", "show", token("pad-1"), "--plain"])
    let human = await service.run(["controller", "show", token("pad-1")])

    let controller = try json.json()
    let capabilities = try #require(controller["capabilities"] as? [String: Any])
    #expect(capabilities["outputOwner"] as? String == "System")
    #expect(plain.standardOutput.contains("\noutput-owner\tsystem\n"))
    #expect(
      Self.rows(
        human,
        endingIn: CLILocalized.text("platform.macos.cli.controller.show.outputOwnerMacos")
      )
      .count == 1
    )
  }

  @Test
  func showSaysNothingAboutOutputOwnerWhenOJDDrivesOutput() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])

    let json = await service.run(["controller", "show", token("pad-1"), "--json"])
    let human = await service.run(["controller", "show", token("pad-1")])

    let controller = try json.json()
    let capabilities = try #require(controller["capabilities"] as? [String: Any])
    #expect(capabilities["outputOwner"] as? String == "OJD")
    let label = CLILocalized.text("cli.controller.show.labelOutputOwner")
    #expect(!human.standardOutput.contains(label))
  }

  private static func rows(_ result: CLIRun, endingIn value: String) -> [Substring] {
    result.standardOutput.split(separator: "\n").filter { $0.hasSuffix("  " + value) }
  }
}
