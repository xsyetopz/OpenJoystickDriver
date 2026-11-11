import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// `ojd controller show VVVV:PPPP` for a connected device that OJD does not serve.
struct ControllerShowUnservedTests {
  private static let gamepad = ProtocolBindingResult.InterfaceSummary(
    PhysicalInterfaceSignature(
      interfaceClass: 3,
      interfaceSubclass: 0,
      interfaceProtocol: 0,
      hostTransport: .usb,
      accessBackend: .hid,
      hidLayout: HIDLayoutSummary(
        hasGamePadOrJoystickCollection: true,
        primaryUsage: HIDUsageSignature(usagePage: 1, usage: 5)
      )
    )
  )

  private static func unbound(
    _ reason: ProtocolBindingReason,
    backend: DeviceAccessBackend = .rawUSB,
    interfaces: [ProtocolBindingResult.InterfaceSummary] = [],
    productID: UInt16 = 0x1010
  ) -> ApplicationServiceUnboundDevice {
    ApplicationServiceUnboundDevice(
      vendorID: 0x3537,
      productID: productID,
      connection: "USB",
      accessBackend: backend,
      reason: reason,
      rejectedCandidates: [],
      interfaces: interfaces
    )
  }

  private static func show(
    _ devices: [ApplicationServiceUnboundDevice],
    _ options: [String] = [],
    identity: String = "3537:1010"
  ) async throws -> CLIRun {
    let service = try FakeService(devices: [], unboundDevices: devices)
    return await service.run(["controller", "show", identity] + options)
  }

  @Test
  func humanOutputGivesTheReasonTheNextStepAndTheCaptureCommand() async throws {
    let result = try await Self.show([Self.unbound(.noProtocolMatch)])
    #expect(result.code == 0, "\(result.standardError)")
    let out = result.standardOutput
    #expect(out.contains(CLILocalized.text(ProtocolBindingReason.noProtocolMatch.explanationKey)))
    #expect(out.contains(CLILocalized.text(ProtocolBindingReason.noProtocolMatch.nextStepKey)))
    #expect(out.contains("ojd controller capture 3537:1010 --duration 10 --json > capture.jsonl"))
    #expect(!out.contains("record draft"))
  }

  @Test
  func aHIDPadNamesTheDraftCommand() async throws {
    let pad = Self.unbound(
      .descriptorContractMismatch,
      backend: .hid,
      interfaces: [Self.gamepad]
    )
    let result = try await Self.show([pad])
    #expect(result.standardOutput.contains("ojd record draft 3537:1010"))
    #expect(!result.standardOutput.contains("controller capture"))
  }

  @Test
  func jsonValidatesAndCarriesTheReasonAndCommands() async throws {
    let result = try await Self.show([Self.unbound(.noProtocolMatch)], ["--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let json = try result.json()
    #expect(json["kind"] as? String == "UnservedController")
    #expect(json["reason"] as? String == "NoProtocolMatch")
    #expect(json["vendorID"] as? Int == 0x3537)
    #expect(json["captureCommand"] is String)
    #expect(json["draftCommand"] == nil)
  }

  @Test
  func plainRowsCarryTheReasonAndTheCommands() async throws {
    let result = try await Self.show([Self.unbound(.noProtocolMatch)], ["--plain"])
    #expect(result.standardOutput.contains("reason\tno-protocol-match\n"))
    #expect(result.standardOutput.contains("capture-command\tojd controller capture 3537:1010"))
  }

  @Test
  func everyReasonShowsItsSentences() async throws {
    for reason in ProtocolBindingReason.allCases {
      let result = try await Self.show([Self.unbound(reason)])
      #expect(result.code == 0, "\(reason) \(result.standardError)")
      #expect(result.standardOutput.contains(CLILocalized.text(reason.explanationKey)))
      #expect(result.standardOutput.contains(CLILocalized.text(reason.nextStepKey)))
    }
  }

  @Test
  func aDeviceThatIsNeitherConnectedNorUnservedStillFails() async throws {
    let result = try await Self.show([Self.unbound(.noProtocolMatch)], identity: "3537:9999")
    #expect(result.code == 1)
  }

  @Test
  func aConnectedControllerWinsOverAnUnservedDeviceOfTheSameModel() async throws {
    let fixture = try #require(ServingFixture.all.first)
    var device = fixture.device
    device.publication = nil
    let service = try FakeService(
      devices: [device],
      unboundDevices: [
        ApplicationServiceUnboundDevice(
          vendorID: device.vendorID,
          productID: device.productID,
          connection: "USB",
          accessBackend: .rawUSB,
          reason: .noProtocolMatch,
          rejectedCandidates: [],
          interfaces: []
        )
      ]
    )
    let result = await service.run(["controller", "show", device.identity, "--json"])
    #expect(try result.json()["kind"] as? String == "Controller")
  }
}
