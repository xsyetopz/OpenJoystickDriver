import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverCLI

extension VirtualCommandTests {
  private static let unit = "U-AbCd_123-xyzW09q"

  private static func unitService() throws -> FakeService {
    try FakeService(
      devices: [
        FakeService.device(id: "pad-1", unit: unit), FakeService.device(id: "pad-2"),
      ]
    ) { method, _ in
      method == .setVirtualHIDProfileOverride || method == .resetVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: nil,
            live: .generic,
            source: "override",
            failure: nil
          )
        ) : nil
    }
  }

  @Test
  func setWithUnitSelectsByUnitIDAndAsksForThatUnitOnly() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "set", "hid-generic", Self.unit, "--unit", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["controller"] as? String == "pad-1")
    let arguments = try #require(service.arguments(of: .setVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideArguments.self,
      from: arguments
    )
    #expect(sent.runtimeIdentifier == "pad-1")
    #expect(sent.unit)
  }

  @Test
  func resetWithUnitSendsTheUnitFlag() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "reset", "pad-1", "--unit"])

    #expect(result.code == 0, "\(result.standardError)")
    let arguments = try #require(service.arguments(of: .resetVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideResetArguments.self,
      from: arguments
    )
    #expect(sent.runtimeIdentifier == "pad-1")
    #expect(sent.unit)
  }

  @Test(arguments: [
    ["virtual", "set", "hid-generic", "pad-2", "--unit"], ["virtual", "reset", "pad-2", "--unit"],
  ])
  func unitForAControllerWithoutAUnitIDFailsBeforeAsking(arguments: [String]) async throws {
    let service = try Self.unitService()

    let result = await service.run(arguments)

    #expect(result.code == 1)
    #expect(result.standardError.contains("Test Pad has no unit ID"))
    #expect(service.arguments(of: .setVirtualHIDProfileOverride).isEmpty)
    #expect(service.arguments(of: .resetVirtualHIDProfileOverride).isEmpty)
  }

  @Test
  func unitWithAllIsAUsageError() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "reset", "--all", "--unit"])

    #expect(result.code == 64)
  }

  @Test
  func controllerListReportsTheUnitID() async throws {
    let service = try Self.unitService()

    let result = await service.run(["controller", "list", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let controllers = try #require(try result.json()["controllers"] as? [[String: Any]])
    #expect(controllers.map { $0["unit"] as? String } == [Self.unit, nil])
  }
}
