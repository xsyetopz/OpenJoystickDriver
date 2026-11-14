import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `controller show` and `controller list --json` name the processes that hold a controller open
/// and say whether OJD holds it exclusively.
@Suite(.serialized)
struct ControllerHoldersCommandTests {
  static let holders = [
    USBExclusiveOwner(processID: 812, name: "Google Chrome He"),
    USBExclusiveOwner(processID: 1203, name: "OpenJoystickDriv"),
  ]

  static func pad(
    _ sessionState: ControllerSessionState = .active
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      physicalOwnership: .exclusiveHID,
      sessionState: sessionState
    )
    device.holders = holders
    return device
  }

  @Test
  func showNamesHoldersAndSuspendWhenOJDHoldsExclusively() async throws {
    let service = try FakeService(devices: [Self.pad()])

    let human = await service.run(["controller", "show", token("pad-1")])

    #expect(human.code == 0, "\(human.standardError)")
    let lines = human.standardOutput.split(separator: "\n").map(String.init)
    #expect(
      lines.contains {
        $0.hasPrefix(CLILocalized.text("ui.controllers.holders"))
          && $0.hasSuffix("Google Chrome He (process 812), OpenJoystickDriv (process 1203)")
      }
    )
    #expect(lines.contains { $0.hasSuffix(CLILocalized.text("status.controllerExclusive")) })
    #expect(
      lines.contains {
        $0.hasPrefix(CLILocalized.text("cli.controller.show.labelNextStep"))
          && $0.hasSuffix(CLILocalized.format("cli.controller.show.suspendHint", token("pad-1")))
      }
    )
  }

  @Test
  func suspendedShowOffersResumeAndNoExclusiveHold() async throws {
    let service = try FakeService(devices: [Self.pad(.suspended)])

    let human = await service.run(["controller", "show", token("pad-1")])

    #expect(human.code == 0, "\(human.standardError)")
    #expect(!human.standardOutput.contains(CLILocalized.text("status.controllerExclusive")))
    #expect(
      human.standardOutput.contains(
        CLILocalized.format("cli.controller.show.resumeHint", token("pad-1"))
      )
    )
  }

  @Test
  func showPlainListsEachHolderAndTheExclusiveState() async throws {
    let service = try FakeService(devices: [Self.pad()])

    let plain = await service.run(["controller", "show", token("pad-1"), "--plain"])

    #expect(plain.code == 0, "\(plain.standardError)")
    let rows = plain.standardOutput.split(separator: "\n").map(String.init)
    #expect(
      rows.filter { $0.hasPrefix("holder\t") } == [
        "holder\t812\tGoogle Chrome He", "holder\t1203\tOpenJoystickDriv",
      ]
    )
    #expect(rows.contains("holds-exclusively\ttrue"))
  }

  @Test
  func jsonCarriesHoldersAndExclusiveState() async throws {
    let service = try FakeService(devices: [Self.pad()])

    let list = await service.run(["controller", "list", "--json"])
    let show = await service.run(["controller", "show", token("pad-1"), "--json"])

    #expect(list.code == 0, "\(list.standardError)")
    #expect(show.code == 0, "\(show.standardError)")
    let item = try #require(
      (try JSONSerialization.jsonObject(with: Data(list.standardOutput.utf8)) as? [String: Any])?[
        "items"
      ] as? [[String: Any]]
    ).first
    #expect(item?["holdsExclusively"] as? Bool == true)
    #expect(
      (item?["holders"] as? [[String: Any]])?.compactMap { $0["name"] as? String } == [
        "Google Chrome He", "OpenJoystickDriv",
      ]
    )
    let ownership =
      (try JSONSerialization.jsonObject(with: Data(show.standardOutput.utf8)) as? [String: Any])?[
        "ownership"
      ] as? [String: Any]
    #expect(ownership?["holdsExclusively"] as? Bool == true)
    #expect((ownership?["holders"] as? [[String: Any]])?.count == 2)
  }
}
