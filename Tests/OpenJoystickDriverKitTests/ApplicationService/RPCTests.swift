import Darwin
import Foundation
import Testing

@testable import OpenJoystickDriverKit

@Suite(.serialized) struct LocalServiceRPCTests {
  @Test func roundTripUsesPrivateSocketAndBoundedJSONFrame() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        let value = try? JSONDecoder().decode(String.self, from: request.arguments)
        let result = value.flatMap { try? JSONEncoder().encode($0.uppercased()) }
        completion(LocalServiceRPCResponse(result: result, error: result == nil ? "decode" : nil))
      }
    )
    try server.start()
    defer { server.stop() }

    let result: String = try await LocalServiceRPCClient.call(
      method: "uppercase",
      arguments: "controller",
      timeoutSeconds: 1,
      socketPath: socketPath
    )
    let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)

    #expect(result == "CONTROLLER")
    #expect(attributes[.posixPermissions] as? Int == 0o600)
  }

  @Test func rejectedPeerReceivesNoApplicationResponse() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in false },
      handler: { _, completion in completion(LocalServiceRPCResponse(result: Data(), error: nil)) }
    )
    try server.start()
    defer { server.stop() }

    await #expect(throws: (any Error).self) {
      let _: Data = try await LocalServiceRPCClient.call(
        method: "rejected",
        arguments: LocalServiceRPCEmptyArguments(),
        timeoutSeconds: 1,
        socketPath: socketPath
      )
    }
  }

  @Test func secondServerCannotDisplaceLiveSocketOwner() throws {
    let socketPath = temporarySocketPath()
    let first = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _, completion in
        completion(LocalServiceRPCResponse(result: Data(), error: nil))
      }
    )
    let second = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { _, completion in
        completion(LocalServiceRPCResponse(result: Data(), error: nil))
      }
    )
    try first.start()
    defer { first.stop() }

    do {
      try second.start()
      Issue.record("Expected the live RPC socket owner to reject a second server.")
      second.stop()
    } catch LocalServiceRPCError.alreadyRunning {
      #expect(LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath) == getpid())
    } catch {
      Issue.record("Unexpected second-server error: \(error)")
    }
  }

  @Test func oversizedFrameIsRejectedBeforeWrite() throws {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    defer { Darwin.close(descriptor) }
    let data = Data(count: LocalServiceRPCTransport.maximumFrameBytes + 1)

    #expect(throws: (any Error).self) {
      try LocalServiceRPCTransport.sendFrame(data, to: descriptor)
    }
  }

  @Test func typedPermissionRequestRoundTripsThroughClient() async throws {
    let socketPath = temporarySocketPath()
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request, completion in
        #expect(request.method == "requestAccess")
        do {
          let arguments = try JSONDecoder().decode(
            LocalServiceRPCPermissionArguments.self,
            from: request.arguments
          )
          #expect(arguments.requirement == .inputMonitoring)
          let snapshot = PermissionManager.Snapshot(
            inputMonitoring: .denied,
            accessibility: .granted
          )
          completion(
            LocalServiceRPCResponse(result: try JSONEncoder().encode(snapshot), error: nil)
          )
        } catch {
          completion(LocalServiceRPCResponse(result: nil, error: error.localizedDescription))
        }
      }
    )
    try server.start()
    defer { server.stop() }

    let client = ApplicationServiceClient(socketPath: socketPath)
    client.connect()
    #expect(client.isConnected)
    #expect(
      try await client.requestAccess(.inputMonitoring)
        == PermissionManager.Snapshot(inputMonitoring: .denied, accessibility: .granted)
    )
  }

  private func temporarySocketPath() -> String {
    "/tmp/com.openjoystickdriver.test.\(UUID().uuidString).rpc"
  }
}
