import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.removingTemporarySockets)
struct ServiceConnectionTests {
  /// With nothing listening on the socket, `open()` reports the service as stopped after one
  /// probe: it adds no wait and no retry.
  @Test
  func aStoppedServiceIsUnavailableAfterOneProbe() async {
    let client = ApplicationServiceClient(socketPath: temporarySocketPath())

    await #expect(throws: CLIFailure.serviceUnavailable) {
      _ = try await ServiceConnection.open(client: client)
    }

    #expect(client.unansweredProbeCount == 1)
  }

  /// `--timeout` bounds each reply, so a busy service gets the time the user gave it; a shorter
  /// `--timeout` keeps the client's own reply limit.
  @Test(arguments: [(30.0, 30.0), (0.5, 5.0)])
  func eachReplyWaitsForTimeoutOption(timeout: Double, replyLimit: Double) async throws {
    let service = try FakeService(devices: [])
    var context = CLIContext()
    context.timeout = timeout
    let client = try await ServiceConnection.$socketPath.withValue(service.socketPath) {
      try await CLIContext.$current.withValue(context) { try await ServiceConnection.open() }
    }
    defer { client.disconnect() }
    #expect(client.replyTimeoutSeconds == replyLimit)
  }
}
