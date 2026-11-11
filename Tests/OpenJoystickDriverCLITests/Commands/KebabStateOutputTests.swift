import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `--plain` and human output spell a state in kebab-case, while `--json` keeps the
/// UpperCamelCase value.
@Suite(.serialized)
struct KebabStateOutputTests {
  private func runStatus(_ service: FakeService, _ arguments: [String]) async -> CLIRun {
    let records = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    return await RecordStore.$directory.withValue(records) {
      await StatusCommand.$extensionProbe.withValue(
        { ExtensionStatus(bundle: .present, registration: .absent) },
        operation: {
          await StatusCommand.$linkProbe.withValue(
            {
              CommandLineToolLinkStatus.probe(
                path: "/nonexistent",
                executable: URL(fileURLWithPath: "/nonexistent")
              )
            },
            operation: { await service.run(["status"] + arguments) }
          )
        }
      )
    }
  }

  @Test
  func theUnboundReasonIsKebabCaseInPlainAndHumanOutput() async throws {
    let unbound = ApplicationServiceUnboundDevice(
      vendorID: 0x1234,
      productID: 0x5678,
      connection: "USB",
      accessBackend: .hid,
      reason: .noProtocolMatch,
      rejectedCandidates: [],
      interfaces: []
    )
    let service = try FakeService(devices: [], unboundDevices: [unbound])
    let json = await runStatus(service, ["--json"])
    let plain = await runStatus(service, ["--plain"])
    let human = await runStatus(service, [])

    #expect(json.code == 0, "\(json.standardError)")
    let devices = try #require(try json.json()["unboundDevices"] as? [[String: Any]])
    #expect(devices.first?["reason"] as? String == "NoProtocolMatch")
    #expect(plain.standardOutput.contains("\tUSB\tno-protocol-match\n"))
    #expect(human.standardOutput.contains("USB  no-protocol-match"))
    #expect(!plain.standardOutput.contains("NoProtocolMatch"))
    #expect(!human.standardOutput.contains("NoProtocolMatch"))
  }

  @Test
  func theUnboundDeviceNameIsInJSONOnlyWhenObserved() async throws {
    func device(_ productID: UInt16, name: String?) -> ApplicationServiceUnboundDevice {
      ApplicationServiceUnboundDevice(
        vendorID: 0x2DC8,
        productID: productID,
        name: name,
        connection: "USB",
        accessBackend: .rawUSB,
        reason: .deviceInUse,
        rejectedCandidates: [],
        interfaces: []
      )
    }
    let service = try FakeService(
      devices: [],
      unboundDevices: [
        device(0x310A, name: "8BitDo Ultimate 2C Wireless Controller"), device(0x301C, name: nil),
      ]
    )
    let json = await runStatus(service, ["--json"])
    let devices = try #require(try json.json()["unboundDevices"] as? [[String: Any]])
    #expect(devices.first?["name"] as? String == "8BitDo Ultimate 2C Wireless Controller")
    #expect(devices.last?["name"] == nil)
  }

  @Test
  func aDeviceHeldByAnotherProgramIsExplainedInHumanOutputOnly() async throws {
    let held = ApplicationServiceUnboundDevice(
      vendorID: 0x3537,
      productID: 0x1010,
      connection: "USB",
      accessBackend: .rawUSB,
      reason: .deviceInUse,
      rejectedCandidates: [],
      interfaces: []
    )
    let service = try FakeService(devices: [], unboundDevices: [held])
    let human = await runStatus(service, [])
    let plain = await runStatus(service, ["--plain"])

    #expect(human.standardOutput.contains("USB  device-in-use"))
    #expect(human.standardOutput.contains(CLILocalized.text("ui.controllers.deviceInUse")))
    #expect(plain.standardOutput.contains("\tUSB\tdevice-in-use\n"))
    #expect(!plain.standardOutput.contains(CLILocalized.text("ui.controllers.deviceInUse")))
  }

  @Test
  func anInterfaceContractMismatchIsExplainedWithANextStepInHumanOutputOnly() async throws {
    let unbound = ApplicationServiceUnboundDevice(
      vendorID: 0x3537,
      productID: 0x1022,
      connection: "USB",
      accessBackend: .hid,
      reason: .interfaceContractMismatch,
      rejectedCandidates: [],
      interfaces: []
    )
    let service = try FakeService(devices: [], unboundDevices: [unbound])
    let human = await runStatus(service, [])
    let plain = await runStatus(service, ["--plain"])
    let sentence = CLILocalized.text("ui.controllers.interfaceContractMismatch")
    let nextStep = CLILocalized.text("ui.controllers.interfaceContractMismatch.nextStep")

    #expect(sentence != "ui.controllers.interfaceContractMismatch")
    #expect(human.standardOutput.contains(sentence))
    #expect(human.standardOutput.contains(nextStep))
    #expect(!plain.standardOutput.contains(sentence))
  }

  @Test
  func theInputHealthIsKebabCaseInPlainAndHumanOutput() async throws {
    let service = try FakeService(devices: [
      .fixture(id: "pad-1"),
      .fixture(
        id: "pad-2",
        inputHealth: ControllerInputHealth(
          state: .waitingForNeutral,
          failureReason: .missingReports
        )
      ),
    ])
    let json = await service.run(["controller", "show", token("pad-2"), "--json"])
    let healthyPlain = await service.run(["controller", "show", token("pad-1"), "--plain"])
    let plain = await service.run(["controller", "show", token("pad-2"), "--plain"])
    let human = await service.run(["controller", "show", token("pad-2")])

    #expect(json.code == 0, "\(json.standardError)")
    let health = try #require(try json.json()["inputHealth"] as? [String: Any])
    #expect(health["state"] as? String == "WaitingForNeutral")
    #expect(health["failureReason"] as? String == "MissingReports")
    #expect(healthyPlain.standardOutput.contains("\ninput-health\thealthy\n"))
    #expect(plain.standardOutput.contains("\ninput-health\twaiting-for-neutral\n"))
    #expect(human.standardOutput.contains("waiting-for-neutral (missing-reports)"))
  }
}
