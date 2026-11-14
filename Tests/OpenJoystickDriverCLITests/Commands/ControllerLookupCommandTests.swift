import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ControllerLookupCommandTests {
  private static let page =
    "https://github.com/xsyetopz/OpenJoystickDriver/wiki/Supported-Controllers"

  private static func run(_ arguments: [String]) async throws -> CLIRun {
    try await FakeService(devices: []).run(arguments)
  }

  @Test
  func modelWithRecordPrintsThePage() async throws {
    let result = try await Self.run(["controller", "lookup", "2C22:2000", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "ControllerLookup")
    #expect(json["identity"] as? String == "2C22:2000")
    #expect(json["hasRecord"] as? Bool == true)
    #expect(json["url"] as? String == Self.page)
  }

  @Test
  func modelWithoutRecordPrintsTheIssueSearch() async throws {
    let result = try await Self.run(["controller", "lookup", "1234:ABCD"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      result.standardOutput
        == "https://github.com/xsyetopz/OpenJoystickDriver/issues?q=1234:ABCD\n"
    )
  }
}
