import Foundation
import OpenJoystickDriverKit
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
  func showReportsTheEffectiveTuningInJSONPlainAndHumanOutput() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1", tuning: Self.tuning)
    ])

    let json = await service.run(["controller", "show", "pad-1", "--json"])
    let plain = await service.run(["controller", "show", "pad-1", "--plain"])
    let human = await service.run(["controller", "show", "pad-1"])

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
  func showLeavesOutTuningWhenTheRecordSetsNone() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])

    let json = await service.run(["controller", "show", "pad-1", "--json"])
    let plain = await service.run(["controller", "show", "pad-1", "--plain"])

    let controller = try json.json()
    #expect(controller["tuning"] == nil)
    #expect(!plain.standardOutput.contains("\ntuning\t"))
  }

  @Test
  func showNamesMacOSAsTheOutputOwnerNextToTheNarrowedCapabilities() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1", physicalOutputOwner: .macOS)
    ])

    let json = await service.run(["controller", "show", "pad-1", "--json"])
    let plain = await service.run(["controller", "show", "pad-1", "--plain"])
    let human = await service.run(["controller", "show", "pad-1"])

    let controller = try json.json()
    let capabilities = try #require(controller["capabilities"] as? [String: Any])
    #expect(capabilities["outputOwner"] as? String == "macos")
    #expect(plain.standardOutput.contains("\noutput-owner\tmacos\n"))
    #expect(
      Self.rows(human, endingIn: CLILocalized.text("cli.controller.show.output_owner.macos"))
        .count == 1
    )
  }

  @Test
  func showSaysNothingAboutTheOutputOwnerWhenOJDDrivesTheOutput() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(id: "pad-1")
    ])

    let json = await service.run(["controller", "show", "pad-1", "--json"])
    let human = await service.run(["controller", "show", "pad-1"])

    let controller = try json.json()
    let capabilities = try #require(controller["capabilities"] as? [String: Any])
    #expect(capabilities["outputOwner"] as? String == "ojd")
    let label = CLILocalized.text("cli.controller.show.label.output_owner")
    #expect(!human.standardOutput.contains(label))
  }

  private static func rows(_ result: CLIRun, endingIn value: String) -> [Substring] {
    result.standardOutput.split(separator: "\n").filter { $0.hasSuffix("  " + value) }
  }
}
