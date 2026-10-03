import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport

@testable import OpenJoystickDriverCLI

/// A service socket that answers `getStatus` with the controllers `devices` returns and each other
/// method with `respond`, and records every request it received.
final class FakeService: @unchecked Sendable {
  typealias Respond = @Sendable (_ method: ApplicationServiceRPCMethod, _ arguments: Data) -> Data?

  let socketPath = temporarySocketPath()
  private let lock = NSLock()
  private var received: [(ApplicationServiceRPCMethod, Data)] = []
  private var server: LocalServiceRPCServer?

  convenience init(
    devices: [ApplicationServiceDeviceDescription],
    respond: @escaping Respond = { _, _ in nil }
  ) throws {
    try self.init(devices: { devices }, respond: respond)
  }

  /// `devices` runs for each `getStatus` request, so the connected controllers can change.
  init(
    devices: @escaping @Sendable () -> [ApplicationServiceDeviceDescription],
    respond: @escaping Respond = { _, _ in nil }
  ) throws {
    let status: @Sendable () -> Data? = {
      doubleEncoded(
        ApplicationServiceStatusPayload(
          inputMonitoring: "granted",
          accessibility: "granted",
          connectedDevices: devices(),
          userSpaceVirtualDeviceEnabled: true
        )
      )
    }
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { [weak self] request, completion in
        guard let method = ApplicationServiceRPCMethod(rawValue: request.method) else {
          completion(LocalServiceRPCResponse(result: nil, error: "unknown \(request.method)"))
          return
        }
        self?.record(method, request.arguments)
        let result = method == .getStatus ? status() : respond(method, request.arguments)
        completion(
          LocalServiceRPCResponse(
            result: result,
            error: result == nil ? "unexpected \(request.method)" : nil
          )
        )
      }
    )
    try server.start()
    self.server = server
  }

  deinit { server?.stop() }

  /// The arguments of every request for `method`, in order.
  func arguments(of method: ApplicationServiceRPCMethod) -> [Data] {
    lock.withLock { received.filter { $0.0 == method }.map(\.1) }
  }

  func run(_ arguments: [String]) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await CLIRun.run(arguments + ["--timeout", "5"])
    }
  }

  private func record(_ method: ApplicationServiceRPCMethod, _ arguments: Data) {
    lock.withLock { received.append((method, arguments)) }
  }
}

/// `value` encoded as the service encodes it.
func encoded<Value: Encodable>(_ value: Value) -> Data? { try? JSONEncoder().encode(value) }

/// `value` encoded twice, as the service encodes the methods that return JSON `Data`.
func doubleEncoded<Value: Encodable>(_ value: Value) -> Data? {
  (try? JSONEncoder().encode(value)).flatMap(encoded)
}
