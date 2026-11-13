import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `controller list` says when macOS also lists a controller that OJD serves.
@Suite(.serialized)
struct ControllerListSystemListedTests {
  @Test
  func everyFormatNamesControllerThatMacOSAlsoLists() async throws {
    let service = try FakeService(devices: [
      ApplicationServiceDeviceDescription.fixture(
        id: "pad-1",
        hidInputOwnership: .exclusive,
        duplicateExposureRisk: .systemGameController
      ),
      ApplicationServiceDeviceDescription.fixture(id: "pad-2", hidInputOwnership: .exclusive),
    ])

    let json = await service.run(["controller", "list", "--json"])
    let plain = await service.run(["controller", "list", "--plain"])
    let human = await service.run(["controller", "list"])

    #expect(json.code == 0, "\(json.standardError)")
    let items = try #require(json.json()["items"] as? [[String: Any]])
    #expect(items.map { $0["alsoListedBySystem"] as? Bool } == [true, false])
    let rows = plain.standardOutput.split(separator: "\n").map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(rows.map { $0.dropLast().last } == ["also-listed-by-system", ""])
    let lines = human.standardOutput.split(separator: "\n").map(String.init)
    let sentence = CLILocalized.text("status.controllerAlsoListedBySystem")
    #expect(lines.map { $0.hasSuffix("  " + sentence) } == [true, false])
  }
}
