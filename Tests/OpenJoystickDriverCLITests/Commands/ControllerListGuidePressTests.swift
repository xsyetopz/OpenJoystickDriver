import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `controller list` and `controller show` say when a controller waits for its PS or home button.
@Suite(.serialized)
struct ControllerListGuidePressTests {
  @Test
  func everyFormatNamesControllerThatWaitsForItsGuidePress() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(
        id: "pad-1",
        inputHealth: ControllerInputHealth(state: .stale, failureReason: .guideNotPressed)
      ),
      ApplicationServiceDeviceDescription.fixture(id: "pad-2"),
    ])

    let json = await service.run(["controller", "list", "--json"])
    let plain = await service.run(["controller", "list", "--plain"])
    let human = await service.run(["controller", "list"])
    let show = await service.run(["controller", "show", token("pad-1"), "--json"])

    #expect(json.code == 0, "\(json.standardError)")
    let items = try #require(json.json()["items"] as? [[String: Any]])
    #expect(items.map { $0["waitsForGuidePress"] as? Bool } == [true, false])
    let rows = plain.standardOutput.split(separator: "\n").map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(rows.map(\.last) == ["waits-for-guide-press", ""])
    let lines = human.standardOutput.split(separator: "\n").map(String.init)
    let sentence = CLILocalized.text("cli.controller.list.pressGuide")
    #expect(sentence == "Press the PS or home button to start its input.")
    #expect(lines.map { $0.hasSuffix("  " + sentence) } == [true, false])
    let health = try #require(try show.json()["inputHealth"] as? [String: Any])
    #expect(health["failureReason"] as? String == "GuideNotPressed")
  }
}
