import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

extension VirtualCommandTests {
  private static let unitLabel = "AbCd_123-xyzW09q"
  private static let unit = ControllerPortKey.fixture(unitLabel).rawValue

  private static func unitService() throws -> FakeService {
    try FakeService(
      devices: [
        ApplicationServiceDeviceDescription.fixture(id: "pad-1", unit: unitLabel),
        ApplicationServiceDeviceDescription.fixture(id: "pad-2"),
      ]
    ) { method, _ in
      method == .setVirtualHIDProfileOverride || method == .resetVirtualHIDProfileOverride
        ? encoded(
          VirtualHIDProfileOverrideResult(
            requested: nil,
            live: .generic,
            source: .override,
            failure: nil
          )
        ) : nil
    }
  }

  @Test
  func setWithUnitSelectsByUnitIDAndAsksForThatUnitOnly() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "set", "generic", Self.unit, "--unit", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["controller"] as? String == token("pad-1"))
    let arguments = try #require(service.arguments(of: .setVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideArguments.self,
      from: arguments
    )
    #expect(sent.controller == .session(.fixture("pad-1")))
    #expect(sent.unit)
  }

  @Test
  func resetWithUnitSendsUnitFlag() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "reset", token("pad-1"), "--unit"])

    #expect(result.code == 0, "\(result.standardError)")
    let arguments = try #require(service.arguments(of: .resetVirtualHIDProfileOverride).first)
    let sent = try JSONDecoder().decode(
      LocalServiceRPCVirtualHIDProfileOverrideResetArguments.self,
      from: arguments
    )
    #expect(sent.controller == .session(.fixture("pad-1")))
    #expect(sent.unit)
  }

  @Test(arguments: [
    ["virtual", "set", "generic", token("pad-2"), "--unit"],
    ["virtual", "reset", token("pad-2"), "--unit"],
  ])
  func unitForControllerWithoutUnitIDFailsBeforeAsking(arguments: [String]) async throws {
    let service = try Self.unitService()

    let result = await service.run(arguments)

    #expect(result.code == 1)
    #expect(result.standardError.contains("Test Pad"))
    #expect(service.arguments(of: .setVirtualHIDProfileOverride).isEmpty)
    #expect(service.arguments(of: .resetVirtualHIDProfileOverride).isEmpty)
  }

  @Test
  func unitWithAllIsUsageError() async throws {
    let service = try Self.unitService()

    let result = await service.run(["virtual", "reset", "--all", "--unit"])

    #expect(result.code == 64)
  }

  @Test
  func controllerListReportsUnitID() async throws {
    let service = try Self.unitService()

    let result = await service.run(["controller", "list", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    let controllers = try #require(try result.json()["items"] as? [[String: Any]])
    #expect(controllers.map { $0["unit"] as? String } == [Self.unit, nil])
  }
}
