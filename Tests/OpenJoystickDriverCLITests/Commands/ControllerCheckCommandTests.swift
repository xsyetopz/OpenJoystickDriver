import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite
struct ControllerCheckCommandTests {
  private func service() throws -> FakeService {
    let pad = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      capabilities: ControllerCapabilities(controls: [.south, .leftStickX, .leftStickY])
    )
    return try FakeService(devices: [pad]) { method, _ in
      method == .getControllerState ? doubleEncoded(ControllerState.neutral) : nil
    }
  }

  @Test
  func refusesAControllerThatDeclaresNoControl() async throws {
    let bare = try FakeService(devices: [ApplicationServiceDeviceDescription.fixture(id: "pad-1")])
    { _, _ in nil }
    let result = await bare.run(["controller", "check", token("pad-1")])
    #expect(result.code == 1)
    #expect(result.standardError.contains("Test Pad"))
  }

  @Test
  func skipsEachControlThatNeverMoves() async throws {
    let result = try await service().run([
      "controller", "check", token("pad-1"), "--duration", "0.05", "--json",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "ControllerCheck")
    let steps = try #require(json["steps"] as? [[String: Any]])
    #expect(!steps.isEmpty)
    #expect(steps.allSatisfy { $0["outcome"] as? String == "Skipped" })
  }

  @Test
  func reportsAPressedControlAsRespondedAndTheRestSkipped() async throws {
    let reads = Counter()
    let pad = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      capabilities: ControllerCapabilities(controls: [.south, .leftStickX, .leftStickY])
    )
    let service = try FakeService(devices: [pad]) { method, _ in
      guard method == .getControllerState else { return nil }
      return doubleEncoded(
        reads.next() == 2 ? ControllerState(pressed: [.south]) : ControllerState.neutral
      )
    }
    let result = await service.run([
      "controller", "check", token("pad-1"), "--duration", "2", "--json",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    let steps = try #require(try result.json()["steps"] as? [[String: Any]])
    #expect(steps.map { $0["control"] as? String } == ["South", "LeftStick"])
    #expect(steps.map { $0["outcome"] as? String } == ["Responded", "Skipped"])
  }

  @Test
  func offersNoValidationAfterACheckWithASkippedControl() async throws {
    let result = try await service().run([
      "controller", "check", token("pad-1"), "--duration", "0.05", "--validate", "--no-input",
    ])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      result.standardError.contains(CLILocalized.text("cli.controller.check.validateUnavailable"))
    )
    #expect(!result.standardError.contains(ControllerCheckIssue.newIssue))
  }

  @Test
  func refusesADurationThatIsNotPositive() async throws {
    let result = try await service().run(["controller", "check", token("pad-1"), "--duration", "0"])
    #expect(result.code != 0)
    #expect(result.standardOutput.isEmpty)
  }
}
