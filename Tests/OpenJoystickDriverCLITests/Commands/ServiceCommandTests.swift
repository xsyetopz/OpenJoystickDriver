import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct ServiceCommandTests {
  private let stoppedExtension: @Sendable () -> ExtensionStatus = {
    ExtensionStatus(bundle: .present, registration: .absent)
  }

  @Test
  func statusReportsAStoppedServiceAsStateAndExitsZero() async throws {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await StatusCommand.$extensionProbe.withValue(stoppedExtension) {
        await CLIRun.run(["status", "--json"])
      }
    }
    #expect(result.code == 0)
    let json = try result.json()
    let service = try #require(json["service"] as? [String: Any])
    #expect(service["state"] as? String == "stopped")
    let extensionState = try #require(json["extension"] as? [String: Any])
    #expect(extensionState["bundle"] as? String == "present")
    #expect(extensionState["registration"] as? String == "absent")
    #expect(json["controllers"] == nil)
  }

  @Test
  func statusReportsTheRunningServiceInJSONAndPlainRows() async throws {
    let socketPath = temporarySocketPath()
    let payload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "denied",
      connectedDevices: [
        ApplicationServiceDeviceDescription(
          name: "Test Pad",
          vendorID: 0x045E,
          productID: 0x028E,
          protocolBinding: ProtocolBindingID(.hidDescriptor),
          connection: "USB",
          discoverySource: .rawUSB,
          serialNumber: nil,
          bindingResult: .hidDescriptorFixture,
          runtimeIdentifier: "pad-1"
        )
      ],
      userSpaceVirtualDeviceEnabled: true
    )
    let result = try JSONEncoder().encode(try JSONEncoder().encode(payload))
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        let isStatus = request.method == ApplicationServiceRPCMethod.getStatus.rawValue
        completion(
          LocalServiceRPCResponse(
            result: isStatus ? result : nil,
            error: isStatus ? nil : "unexpected \(request.method)"
          )
        )
      }
    )
    try server.start()
    defer { server.stop() }

    let (jsonRun, plainRun) = await ServiceConnection.$socketPath.withValue(socketPath) {
      await StatusCommand.$extensionProbe.withValue(stoppedExtension) {
        (
          await CLIRun.run(["status", "--json", "--timeout", "5"]),
          await CLIRun.run(["status", "--plain", "--timeout", "5"])
        )
      }
    }

    #expect(jsonRun.code == 0, "\(jsonRun.standardError)")
    let json = try jsonRun.json()
    let service = try #require(json["service"] as? [String: Any])
    #expect(service["state"] as? String == "running")
    let permissions = try #require(json["permissions"] as? [String: Any])
    #expect(permissions["inputMonitoring"] as? String == "granted")
    #expect(permissions["accessibility"] as? String == "denied")
    let controllers = try #require(json["controllers"] as? [[String: Any]])
    #expect(controllers.count == 1)
    #expect(controllers.first?["id"] as? String == "pad-1")
    #expect(controllers.first?["vendorID"] as? Int == 0x045E)

    #expect(plainRun.code == 0, "\(plainRun.standardError)")
    let rows = plainRun.standardOutput.split(separator: "\n").map {
      $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    }
    #expect(rows.first?.prefix(2) == ["service", "running"])
    #expect(rows.contains(["permission", "accessibility", "denied"]))
    #expect(rows.contains(["controller", "pad-1", "045E:028E", "USB", "Test Pad"]))
  }

  @Test(arguments: ["start", "wait"])
  func startAndWaitReportARunningService(verb: String) async throws {
    let service = try FakeService(devices: [])
    let result = await service.run(["service", verb, "--json"])
    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["state"] as? String == "running")
  }

  @Test
  func waitWithoutAServiceExitsSixtyNineAfterTheTimeout() async {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(["service", "wait", "--timeout", "0.2"])
    }
    #expect(result.code == 69)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("ojd: "))
    #expect(result.standardError.contains("ojd service start"))
  }

  @Test
  func stopWithoutAServiceReportsStopped() async throws {
    let result = await ServiceConnection.$socketPath.withValue(temporarySocketPath()) {
      await CLIRun.run(["service", "stop", "--json"])
    }
    #expect(result.code == 0)
    #expect(try result.json()["state"] as? String == "stopped")
  }

  @Test
  func quietSuppressesTheSuccessMessage() async {
    let path = temporarySocketPath()
    let loud = await ServiceConnection.$socketPath.withValue(path) {
      await CLIRun.run(["service", "stop"])
    }
    let quiet = await ServiceConnection.$socketPath.withValue(path) {
      await CLIRun.run(["service", "stop", "--quiet"])
    }
    #expect(loud.code == 0 && quiet.code == 0)
    #expect(!loud.standardError.isEmpty)
    #expect(loud.standardOutput.isEmpty)
    #expect(quiet.standardError.isEmpty && quiet.standardOutput.isEmpty)
  }

  @Test
  func applicationBundleFollowsTheInstalledLink() {
    let executable = URL(
      fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
    )
    #expect(
      ServiceStartCommand.applicationBundleURL(executableURL: executable)?.path
        == "/Applications/OpenJoystickDriver.app"
    )
    #expect(
      ServiceStartCommand.applicationBundleURL(
        executableURL: URL(fileURLWithPath: "/repo/.build/debug/OpenJoystickDriver")
      ) == nil
    )
  }
}
