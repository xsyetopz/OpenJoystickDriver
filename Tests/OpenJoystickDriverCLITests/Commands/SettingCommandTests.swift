import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct SettingCommandTests {
  /// A service whose settings start as `settings` and that applies each `setSetting` unless the
  /// key is in `refused`; it records the methods it received.
  private func serve(
    settings: [ApplicationSettingKey: Bool] = [:],
    refused: Set<ApplicationSettingKey> = [],
    socketPath: String,
    received: Locked<[String]> = Locked([])
  ) throws -> LocalServiceRPCServer {
    let state = Locked(settings)
    let payload: @Sendable () throws -> Data = {
      let values = state.withLock { current in
        ApplicationSettingKey.allCases.map {
          ApplicationSettingValue(key: $0, value: current[$0] ?? $0.defaultValue)
        }
      }
      return try JSONEncoder().encode(ApplicationSettingsPayload(settings: values))
    }
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        received.withLock { $0.append(request.method) }
        switch request.method {
        case ApplicationServiceRPCMethod.getSettings.rawValue:
          return LocalServiceRPCResponse(result: try? payload(), error: nil)
        case ApplicationServiceRPCMethod.setSetting.rawValue:
          if let arguments = try? JSONDecoder().decode(
            ApplicationServiceSettingArguments.self,
            from: request.arguments
          ), !refused.contains(arguments.key) {
            state.withLock { $0[arguments.key] = arguments.value }
          }
          return LocalServiceRPCResponse(result: try? payload(), error: nil)
        default:
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
        }
      }
    )
    try server.start()
    return server
  }

  private func run(_ arguments: [String], socketPath: String) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await CLIRun.run(arguments + testServerTimeout)
    }
  }

  @Test
  func listPrintsEverySettingInEachFormat() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(settings: [.launchAtLogin: true], socketPath: socketPath)
    defer { server.stop() }

    let json = await run(["setting", "list", "--json"], socketPath: socketPath)
    let plain = await run(["setting", "list", "--plain"], socketPath: socketPath)
    let human = await run(["setting", "list"], socketPath: socketPath)

    #expect(json.code == 0, "\(json.standardError)")
    let settings = try #require(try json.json()["items"] as? [[String: Any]])
    #expect(settings.count == ApplicationSettingKey.allCases.count)
    let login = try #require(settings.first { $0["key"] as? String == "launchAtLogin" })
    #expect(login["value"] as? Bool == true)
    #expect(login["description"] is String)
    #expect(plain.standardOutput.contains("launchAtLogin\ttrue\n"))
    #expect(human.code == 0)
    #expect(human.standardOutput.contains("launchAtLogin"))
    #expect(human.standardError.isEmpty)
  }

  @Test
  func getPrintsBareValueOrJSON() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(settings: [.developerTools: true], socketPath: socketPath)
    defer { server.stop() }

    let human = await run(["setting", "get", "developerTools"], socketPath: socketPath)
    let json = await run(["setting", "get", "developerTools", "--json"], socketPath: socketPath)

    #expect(human.code == 0)
    #expect(human.standardOutput == "true\n")
    #expect(try json.json()["key"] as? String == "developerTools")
    #expect(try json.json()["value"] as? Bool == true)
  }

  @Test
  func setAppliesValueAndReportsOnStandardError() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(socketPath: socketPath, received: received)
    defer { server.stop() }

    let result = await run(["setting", "set", "launchAtLogin", "true"], socketPath: socketPath)
    let after = await run(["setting", "get", "launchAtLogin"], socketPath: socketPath)

    #expect(result.code == 0, "\(result.standardError)")
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("launchAtLogin"))
    #expect(after.standardOutput == "true\n")
    #expect(received.withLock { $0.contains(ApplicationServiceRPCMethod.setSetting.rawValue) })
  }

  @Test
  func setPrintsNewValueAsJSON() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath, received: Locked<[String]>([]))
    defer { server.stop() }

    let result = await run(
      ["setting", "set", "notify.sounds", "false", "--json"],
      socketPath: socketPath
    )

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["key"] as? String == "notify.sounds")
    #expect(try result.json()["value"] as? Bool == false)
  }

  @Test
  func showInDockIsSettingKeyThatDefaultsToOff() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(socketPath: socketPath, received: Locked<[String]>([]))
    defer { server.stop() }

    let get = await run(["setting", "get", "showInDock", "--json"], socketPath: socketPath)
    let set = await run(["setting", "set", "showInDock", "true", "--json"], socketPath: socketPath)

    #expect(get.code == 0, "\(get.standardError)")
    #expect(try get.json()["key"] as? String == "showInDock")
    #expect(try get.json()["value"] as? Bool == false)
    #expect(set.code == 0, "\(set.standardError)")
    #expect(try set.json()["value"] as? Bool == true)
  }

  @Test
  func setExitsOneWhenMacOSLeavesSettingOff() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(refused: [.launchAtLogin], socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["setting", "set", "launchAtLogin", "true"], socketPath: socketPath)

    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error["))
  }

  @Test(arguments: [
    ["setting", "get", "no-such-key"], ["setting", "set", "no-such-key", "true"],
    ["setting", "set", "launchAtLogin", "yes"], ["setting", "set", "launchAtLogin"],
  ])
  func badKeysAndValuesExitSixtyFourBeforeAnyRequest(arguments: [String]) async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(socketPath: socketPath, received: received)
    defer { server.stop() }

    let result = await run(arguments, socketPath: socketPath)

    #expect(result.code == 64)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2003]: "))
    #expect(received.withLock { $0.isEmpty })
  }

  @Test(arguments: [["setting", "list"], ["setting", "get", "launchAtLogin"]])
  func serviceDownExitsSixtyNine(arguments: [String]) async {
    let result = await run(arguments, socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == CLIFailure.serviceUnavailable.line + "\n")
  }
}
