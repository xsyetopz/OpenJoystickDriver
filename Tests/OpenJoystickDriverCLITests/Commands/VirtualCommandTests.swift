import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct VirtualCommandTests {
  @Test
  func setSendsTheProfileForTheSelectedControllerAndPrintsTheResult() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .setVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: .generic,
            live: .generic,
            source: "override",
            failure: nil
          )
        ) : nil
    }
    let result = await service.run(["virtual", "set", "hid-generic", "pad-1", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["controller"] as? String == "pad-1")
    #expect(json["live"] as? String == "hid-generic")
    #expect(json["source"] as? String == "override")
    let arguments = try #require(service.arguments(of: .setVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideArguments.self,
      from: arguments
    )
    #expect(sent.profile == "hid-generic")
    #expect(sent.runtimeIdentifier == "pad-1")
  }

  @Test
  func aRejectedProfileFailsWithExitOne() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { method, _ in
      method == .setVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: .generic,
            live: nil,
            source: "automatic",
            failure: .activationFailed(detail: "no fit")
          )
        ) : nil
    }
    let result = await service.run(["virtual", "set", "hid-generic", "pad-1"])
    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("no fit"))
  }

  @Test
  func resetAllWithForceClearsEveryChoice() async throws {
    let service = try FakeService(devices: []) { method, _ in
      method == .resetSettings ? encoded(true) : nil
    }
    let result = await service.run(["virtual", "reset", "--all", "--force", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["reset"] as? String == "all")
    #expect(service.arguments(of: .resetSettings).count == 1)
  }

  @Test
  func resetAllWithoutAPromptOrForceIsAUsageErrorAndChangesNothing() async throws {
    let service = try FakeService(devices: []) { _, _ in encoded(true) }
    let result = await service.run(["virtual", "reset", "--all", "--no-input"])
    #expect(result.code == 64)
    #expect(result.standardError.contains("--force"))
    #expect(service.arguments(of: .resetSettings).isEmpty)
  }

  @Test(arguments: [
    ["virtual", "reset", "--all", "--dry-run"], ["virtual", "reset", "pad-1", "-n"],
  ])
  func aDryRunDescribesTheResetAndChangesNothing(arguments: [String]) async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")]) { _, _ in
      encoded(true)
    }
    let result = await service.run(arguments)
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.hasPrefix("Would return"))
    #expect(service.arguments(of: .resetSettings).isEmpty)
    #expect(service.arguments(of: .resetVirtualHIDProfileOverride).isEmpty)
  }

  @Test(arguments: [
    ["virtual", "reset"], ["virtual", "reset", "pad-1", "--all"],
    ["virtual", "set", "hid-unknown", "pad-1"],
  ])
  func aMissingOrInvalidTargetExitsSixtyFour(arguments: [String]) async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(arguments)
    #expect(result.code == 64, "\(arguments)")
    #expect(service.arguments(of: .getStatus).isEmpty)
  }

  @Test
  func showListsEachControllersProfileAndTheChoices() async throws {
    let service = try FakeService(devices: [FakeService.device(id: "pad-1")])
    let result = await service.run(["virtual", "show", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    #expect(controllers.map { $0["id"] as? String } == ["pad-1"])
    #expect(json["profiles"] as? [String] == VirtualHIDProfileID.allCases.map(\.rawValue))
  }
}
