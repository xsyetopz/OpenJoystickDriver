import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

struct ControllerSendCommandTests {
  private static func answering(
    _ outcome: ControllerOutputResult.Outcome = .delivered
  ) -> FakeService.Respond {
    { method, _ in
      method == .sendRawControllerOutput ? encoded(ControllerOutputResult(outcome)) : nil
    }
  }

  private static func service(
    _ outcome: ControllerOutputResult.Outcome = .delivered
  ) throws -> FakeService {
    try FakeService(devices: [.fixture(id: "pad-1")], respond: answering(outcome))
  }

  private static func sent(_ service: FakeService) throws -> LocalServiceRPCRawOutputArguments {
    let all = service.arguments(of: .sendRawControllerOutput)
    #expect(all.count == 1)
    return try JSONDecoder().decode(LocalServiceRPCRawOutputArguments.self, from: all[0])
  }

  @Test
  func sendsSpacedBytesInOneArgumentAsAnOutputReport() async throws {
    let service = try Self.service()
    let result = await service.run(["controller", "send", token("pad-1"), "51 00 ff"])
    #expect(result.code == 0, "\(result.standardError)")
    let sent = try Self.sent(service)
    #expect(sent.controller == .session(.fixture("pad-1")))
    #expect(
      sent.output == ControllerRawOutput(destination: .hidOutput, bytes: [0x51, 0x00, 0xFF])
    )
  }

  @Test
  func sendsBytesGivenAsSeveralArguments() async throws {
    let service = try Self.service()
    let result = await service.run(["controller", "send", token("pad-1"), "FA", "FE", "00"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try Self.sent(service).output.bytes == [0xFA, 0xFE, 0x00])
  }

  @Test
  func featureFlagSendsAFeatureReport() async throws {
    let service = try Self.service()
    let result = await service.run(
      ["controller", "send", token("pad-1"), "01 02", "--feature", "--report-id", "1"]
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      try Self.sent(service).output
        == ControllerRawOutput(destination: .hidFeature, reportID: 1, bytes: [1, 2])
    )
  }

  @Test
  func usbEndpointSendsAnInterruptPacket() async throws {
    let service = try Self.service()
    let result = await service.run(
      ["controller", "send", token("pad-1"), "09 08", "--usb-endpoint", "2"]
    )
    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      try Self.sent(service).output
        == ControllerRawOutput(destination: .usbInterrupt, endpoint: 2, bytes: [9, 8])
    )
  }

  @Test
  func jsonNamesTheWrite() async throws {
    let service = try Self.service()
    let result = await service.run(["controller", "send", token("pad-1"), "0a ff", "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    let object = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
    )
    let details = try #require(object["details"] as? [String: Any])
    #expect(details["bytes"] as? String == "0A FF")
    #expect(details["destination"] as? String == "hidOutput")
    #expect(details["reportID"] as? Int == 0)
    #expect(details["outcome"] as? String == "Delivered")
  }

  @Test(arguments: [
    ["zz"], ["5"], ["51,00"], [String](repeating: "01", count: 65),
  ])
  func badBytesAreRefusedBeforeAnythingIsSent(_ bytes: [String]) async throws {
    let service = try Self.service()
    let result = await service.run(["controller", "send", token("pad-1")] + bytes)
    #expect(result.code == 64)
    #expect(service.arguments(of: .sendRawControllerOutput).isEmpty)
  }

  @Test
  func reportIDThatDiffersFromTheFirstByteIsRefused() async throws {
    let service = try Self.service()
    let result = await service.run(
      ["controller", "send", token("pad-1"), "52 00", "--report-id", "81"]
    )
    #expect(result.code == 64)
    #expect(service.arguments(of: .sendRawControllerOutput).isEmpty)
  }

  @Test
  func reportIDZeroIsRefused() async throws {
    let service = try Self.service()
    let result = await service.run(
      ["controller", "send", token("pad-1"), "00 01", "--report-id", "0"]
    )
    #expect(result.code == 64)
    #expect(service.arguments(of: .sendRawControllerOutput).isEmpty)
  }

  @Test(arguments: [["--feature"], ["--report-id", "1"]])
  func usbEndpointExcludesHIDOptions(_ options: [String]) async throws {
    let service = try Self.service()
    let result = await service.run(
      ["controller", "send", token("pad-1"), "01 02", "--usb-endpoint", "2"] + options
    )
    #expect(result.code == 64)
    #expect(service.arguments(of: .sendRawControllerOutput).isEmpty)
  }

  @Test
  func writeTheControllerRefusesFails() async throws {
    let service = try Self.service(.writeFailed)
    let result = await service.run(["controller", "send", token("pad-1"), "01"])
    #expect(result.code == 1)
    #expect(result.standardError.contains("write-failed"), "\(result.standardError)")
  }
}
