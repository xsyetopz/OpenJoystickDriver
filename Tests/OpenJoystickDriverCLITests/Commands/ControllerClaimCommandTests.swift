import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ControllerClaimCommandTests {
  /// A user record directory for one test, beside an empty `Packages` store.
  private final class Directory {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-claim-\(UUID().uuidString)",
      isDirectory: true
    )

    var controllers: URL { root.appendingPathComponent("Controllers", isDirectory: true) }
    var file: URL { controllers.appendingPathComponent("2c22-2000.patch.plist") }

    deinit { try? FileManager.default.removeItem(at: root) }
  }

  /// A connected `SonyDualShock4` model, a HID family; `native` makes macOS serve it.
  private static func device(
    vendorID: UInt16 = 0x2C22,
    productID: UInt16 = 0x2000,
    native: Bool
  ) throws -> ApplicationServiceDeviceDescription {
    let fixture = ApplicationServiceDeviceDescription.fixture(
      id: "pad-1",
      vendorID: vendorID,
      productID: productID
    )
    guard native else { return fixture }
    var object = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture)) as? [String: Any]
    )
    object["physicalOwnership"] = ControllerOwnershipObservation.systemGamepad.rawValue
    return try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private static func run(
    _ arguments: [String],
    device: ApplicationServiceDeviceDescription,
    in directory: Directory
  ) async throws -> CLIRun {
    let service = try FakeService(devices: [device])
    return await RecordStore.$directory.withValue(directory.controllers) {
      await service.run(arguments)
    }
  }

  private static func server(in directory: Directory) -> ControllerServer? {
    ControllerRecordSet.load(userDirectory: directory.controllers)
      .records[ControllerModelID(vendorID: 0x2C22, productID: 0x2000)]?.server
  }

  @Test
  func claimWritesTheUserRecord() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "claim", token("pad-1"), "--json"],
      device: Self.device(native: true),
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "ControllerServer")
    #expect(json["identity"] as? String == "2C22:2000")
    #expect(json["server"] as? String == "OJD")
    #expect(json["previous"] as? String == "System")
    #expect(json["created"] as? Bool == true)
    #expect(json["dryRun"] as? Bool == false)
    #expect(json["file"] as? String == directory.file.path)
    #expect(Self.server(in: directory) == .ojd)
  }

  @Test
  func releaseGivesAClaimedModelBack() async throws {
    let directory = Directory()
    let device = try Self.device(native: false)
    _ = try await Self.run(
      ["controller", "claim", token("pad-1")],
      device: Self.device(native: true),
      in: directory
    )
    // OJD seized the controller, so it no longer reports as a native gamepad.
    let result = try await Self.run(
      ["controller", "release", token("pad-1"), "--plain"],
      device: device,
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput == "2C22:2000\tsystem\t\(directory.file.path)\n")
    #expect(Self.server(in: directory) == .system)
  }

  @Test
  func dryRunWritesNothing() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "claim", token("pad-1"), "--dry-run", "--json"],
      device: Self.device(native: true),
      in: directory
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["dryRun"] as? Bool == true)
    #expect(!FileManager.default.fileExists(atPath: directory.file.path))
  }

  @Test
  func rawUSBControllerIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "release", token("pad-1")],
      device: Self.device(vendorID: 0x366C, productID: 0x0005, native: true),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.claimUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func controllerMacOSDoesNotServeIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "claim", token("pad-1")],
      device: Self.device(native: false),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.claimUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func modelWithoutARecordIsRefused() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "claim", token("pad-1")],
      device: Self.device(vendorID: 0x1234, productID: 0xABCD, native: true),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains(ErrorCode.claimUnsupported.rawValue))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func claimRefusesARawUSBControllerWithoutWriting() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "claim", token("pad-1"), "--json"],
      device: Self.device(vendorID: 0x366C, productID: 0x0005, native: true),
      in: directory
    )
    #expect(result.code == 1)
    #expect(result.standardError.contains("E2023"))
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func theOldOwnershipWordIsAnUnknownCommand() async throws {
    let directory = Directory()
    let result = try await Self.run(
      ["controller", "ownership", token("pad-1"), "virtual"],
      device: Self.device(native: true),
      in: directory
    )
    #expect(result.code == 64, "\(result.standardError)")
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func showReportsTheChoiceAndItsSource() async throws {
    let directory = Directory()
    let device = try Self.device(native: true)
    let before = try await Self.run(
      ["controller", "show", token("pad-1"), "--json"],
      device: device,
      in: directory
    )
    let beforeOwnership = try #require(try before.json()["ownership"] as? [String: Any])
    #expect(beforeOwnership["server"] as? String == "System")
    #expect(beforeOwnership["serverSource"] as? String == "Default")

    _ = try await Self.run(
      ["controller", "claim", token("pad-1")],
      device: device,
      in: directory
    )
    let after = try await Self.run(
      ["controller", "show", token("pad-1"), "--json"],
      device: device,
      in: directory
    )
    let afterOwnership = try #require(try after.json()["ownership"] as? [String: Any])
    #expect(afterOwnership["server"] as? String == "OJD")
    #expect(afterOwnership["serverSource"] as? String == "User")

    let plain = try await Self.run(
      ["controller", "show", token("pad-1"), "--plain"],
      device: device,
      in: directory
    )
    #expect(plain.standardOutput.contains("server\tojd\tuser\n"))
  }

  @Test(arguments: [
    (ControllerOwnershipObservation.exclusiveRawUSB, ControllerAccessRoute.rawAccess),
    (.exclusiveHID, .system),
  ])
  func showNamesOJDForAControllerTheSystemDoesNotServe(
    observation: ControllerOwnershipObservation,
    accessRoute: ControllerAccessRoute
  ) async throws {
    var object = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(Self.device(vendorID: 0x3537, productID: 0x1010, native: false))
      ) as? [String: Any]
    )
    object["physicalOwnership"] = observation.rawValue
    object["recordAccessRoute"] = accessRoute.rawValue
    let device = try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
    let directory = Directory()
    let json = try await Self.run(
      ["controller", "show", token("pad-1"), "--json"],
      device: device,
      in: directory
    ).json()
    let ownership = try #require(json["ownership"] as? [String: Any])
    #expect(ownership["server"] as? String == "OJD")
    #expect(ownership["serverSource"] as? String == "Route")
    let plain = try await Self.run(
      ["controller", "show", token("pad-1"), "--plain"],
      device: device,
      in: directory
    )
    #expect(plain.standardOutput.contains("server\tojd\troute\n"))
  }

  /// A connected `045E:02EA` that Apple's driver holds: macOS serves it, and its record reaches it
  /// through OJD's extension.
  private static func appleHeldDevice() throws -> ApplicationServiceDeviceDescription {
    var object = try #require(
      try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(Self.device(vendorID: 0x045E, productID: 0x02EA, native: true))
      ) as? [String: Any]
    )
    object["recordAccessRoute"] = ControllerAccessRoute.extensionOwned.rawValue
    return try JSONDecoder().decode(
      ApplicationServiceDeviceDescription.self,
      from: JSONSerialization.data(withJSONObject: object)
    )
  }

  private static func runSubmitting(
    _ arguments: [String],
    outcome: SystemExtensionSetupRequestResult,
    actions: Locked<[TransportExtensionSubmission.Action]>,
    in directory: Directory
  ) async throws -> CLIRun {
    let submission:
      @Sendable (TransportExtensionSubmission.Action) async ->
        SystemExtensionSetupRequestResult = { action in
          actions.withLock { $0.append(action) }
          return outcome
        }
    return try await TransportExtensionSubmission.$submit.withValue(submission) {
      try await Self.run(arguments, device: Self.appleHeldDevice(), in: directory)
    }
  }

  @Test
  func claimOfAModelAppleHoldsSendsTheActivationRequestAndWritesNoRecord() async throws {
    let directory = Directory()
    let actions = Locked<[TransportExtensionSubmission.Action]>([])

    let result = try await Self.runSubmitting(
      ["controller", "claim", token("pad-1"), "--json"],
      outcome: .awaitingApproval,
      actions: actions,
      in: directory
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["state"] as? String == "AwaitingApproval")
    #expect(actions.withLock { $0 } == [.activate])
    #expect(!FileManager.default.fileExists(atPath: directory.controllers.path))
  }

  @Test
  func releaseOfAModelAppleHoldsSendsNoRequest() async throws {
    let directory = Directory()
    let actions = Locked<[TransportExtensionSubmission.Action]>([])

    let result = try await Self.runSubmitting(
      ["controller", "release", token("pad-1")],
      outcome: .active,
      actions: actions,
      in: directory
    )

    #expect(result.code == 1)
    #expect(actions.withLock { $0 }.isEmpty)
  }

  @Test
  func showNamesAModelAppleHoldsAsServedByMacOS() async throws {
    let directory = Directory()
    let device = try Self.appleHeldDevice()
    let plain = try await Self.run(
      ["controller", "show", token("pad-1"), "--plain"],
      device: device,
      in: directory
    )
    let human = try await Self.run(
      ["controller", "show", token("pad-1")],
      device: device,
      in: directory
    )

    #expect(plain.standardOutput.contains("served-by\tmacos\n"))
    #expect(plain.standardOutput.contains("serving-route\tnative-pass-through"))
    #expect(human.standardOutput.contains("Served by"))
    #expect(human.standardOutput.contains("macOS. Run `ojd controller claim "))
  }
}
