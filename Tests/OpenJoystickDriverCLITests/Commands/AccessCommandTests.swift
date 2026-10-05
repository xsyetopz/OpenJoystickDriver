import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct AccessCommandTests {
  private static let team = CodeSigningIdentity(
    kind: .team,
    identifier: "com.example.reader",
    teamIdentifier: "ABCDE12345"
  )
  private static let grant = AccessGrantSummary(
    AccessGrant(
      identity: team,
      scopes: [.read],
      grantedAt: "2026-10-03T20:00:00Z",
      path: "/Applications/Reader.app"
    )
  )
  private static let refused = AccessRefusedClient(
    identity: CodeSigningIdentity(kind: .adHoc, identifier: "tool", teamIdentifier: nil),
    path: "/tmp/tool",
    scopes: [.read],
    reason: "E1002",
    refusedAt: "2026-10-03T20:01:00Z"
  )
  private static let token = AccessTokenSummary(
    name: "overlay",
    origins: ["http://localhost:8080"],
    scopes: [.read],
    grantedAt: "2026-10-03T20:02:00Z"
  )
  private static let refusedToken = AccessRefusedToken(
    name: nil,
    origin: "http://evil.example",
    transport: .web,
    scopes: [.read],
    reason: "E1002",
    refusedAt: "2026-10-03T20:03:00Z"
  )

  /// A service with one grant and one refused client that answers each access method.
  private func service() throws -> FakeService {
    try FakeService(devices: []) { method, arguments in
      let status = { (enabled: Bool, web: Bool) in
        AccessStatusPayload(
          enabled: enabled,
          socketPath: "/tmp/endpoint.sock",
          connections: [AccessConnection(identity: Self.team, scopes: [.read])],
          grants: [Self.grant],
          refused: [Self.refused],
          web: AccessWebStatus(
            enabled: web,
            listening: web,
            port: 47_614,
            pagesPath: "/tmp/Overlays"
          ),
          tokens: [Self.token],
          refusedTokens: [Self.refusedToken]
        )
      }
      switch method {
      case .getAccessStatus: return encoded(status(true, false))
      case .setAccessEnabled:
        let value = try? JSONDecoder().decode(AccessEnabledArguments.self, from: arguments)
        return encoded(status(value?.enabled ?? false, false))
      case .setWebAccess:
        let value = try? JSONDecoder().decode(AccessWebArguments.self, from: arguments)
        return encoded(status(true, value?.enabled ?? false))
      case .grantTokenAccess:
        guard
          let value = try? JSONDecoder().decode(AccessTokenGrantArguments.self, from: arguments)
        else { return nil }
        return encoded(
          AccessTokenGrantResult(
            token: "ojd_secret",
            grant: AccessTokenSummary(
              name: value.name,
              origins: value.origins,
              scopes: value.scopes,
              grantedAt: "now"
            )
          )
        )
      case .grantAccess:
        guard let value = try? JSONDecoder().decode(AccessGrantArguments.self, from: arguments)
        else { return nil }
        return encoded(
          AccessGrantSummary(
            AccessGrant(
              identity: value.identity,
              scopes: value.scopes,
              grantedAt: "now",
              path: value.path
            )
          )
        )
      case .revokeAccess:
        guard let value = try? JSONDecoder().decode(AccessRevokeArguments.self, from: arguments)
        else { return nil }
        let left =
          value.scopes.map { removed in Self.grant.scopes.filter { !removed.contains($0) } } ?? []
        if value.id == Self.token.id {
          return encoded(
            AccessRevokeResult(id: value.id, grant: nil, token: nil, closedConnections: 2)
          )
        }
        return encoded(
          AccessRevokeResult(
            id: value.id,
            grant: left.isEmpty
              ? nil
              : AccessGrantSummary(
                AccessGrant(
                  identity: Self.team,
                  scopes: left,
                  grantedAt: "now",
                  path: Self.grant.path
                )
              ),
            closedConnections: 1
          )
        )
      default: return nil
      }
    }
  }

  @Test
  func statusAndListPrintEachFormat() async throws {
    let service = try service()

    let status = await service.run(["access", "status", "--json"])
    let list = await service.run(["access", "list", "--json"])
    let plain = await service.run(["access", "list", "--plain"])
    let human = await service.run(["access", "status"])

    #expect(status.code == 0, "\(status.standardError)")
    #expect(try status.json()["socketPath"] as? String == "/tmp/endpoint.sock")
    #expect(
      (try list.json()["grants"] as? [[String: Any]])?.first?["id"] as? String == Self.grant.id
    )
    #expect((try list.json()["refused"] as? [[String: Any]])?.first?["kind"] as? String == "ad-hoc")
    #expect(plain.standardOutput.contains("granted\t\(Self.grant.id)\tteam\tcom.example.reader"))
    #expect(plain.standardOutput.contains("token\ttoken:overlay\thttp://localhost:8080\tread"))
    #expect(plain.standardOutput.contains("refused-token\t\thttp://evil.example\tread\tweb"))
    #expect(
      (try list.json()["tokens"] as? [[String: Any]])?.first?["id"] as? String == "token:overlay"
    )
    #expect((try status.json()["web"] as? [String: Any])?["port"] as? Int == 47_614)
    #expect(human.standardOutput.contains("/tmp/endpoint.sock"))
    #expect(human.standardOutput.contains("WebSocket: off"))
  }

  @Test
  func grantingATokenNeedsForceAndPrintsTheTokenOnce() async throws {
    let service = try service()

    let refused = await service.run(["access", "grant", "--token", "overlay", "--no-input"])
    let json = await service.run([
      "access", "grant", "--token", "overlay", "--origin", "http://localhost:8080", "--force",
      "--json",
    ])
    let human = await service.run(["access", "grant", "--token", "bot", "--force"])

    #expect(refused.code == 64)
    #expect(json.code == 0, "\(json.standardError)")
    #expect(try json.json()["token"] as? String == "ojd_secret")
    #expect((try json.json()["grant"] as? [String: Any])?["id"] as? String == "token:overlay")
    #expect(human.standardOutput.components(separatedBy: "ojd_secret").count == 2)
    let sent = try service.arguments(of: .grantTokenAccess).map {
      try JSONDecoder().decode(AccessTokenGrantArguments.self, from: $0)
    }
    #expect(sent.map(\.name) == ["overlay", "bot"])
    #expect(sent.map(\.origins) == [["http://localhost:8080"], []])
    #expect(service.arguments(of: .grantAccess).isEmpty)
  }

  @Test(arguments: [
    ["access", "grant", "--force"],
    ["access", "grant", Self.grant.id, "--token", "overlay", "--force"],
    ["access", "grant", Self.grant.id, "--origin", "http://localhost:8080", "--force"],
  ])
  func grantNeedsEitherAClientOrAToken(arguments: [String]) async throws {
    let service = try service()

    let result = await service.run(arguments)

    #expect(result.code == 64)
    #expect(service.arguments(of: .grantAccess).isEmpty)
    #expect(service.arguments(of: .grantTokenAccess).isEmpty)
  }

  @Test
  func aTokenWithOriginsCannotAskForControl() async throws {
    let service = try service()

    let result = await service.run([
      "access", "grant", "--token", "pad", "--origin", "http://localhost:8080", "--scope",
      "control", "--force",
    ])

    #expect(result.code == 64)
    #expect(result.standardError.contains("--origin"))
    #expect(service.arguments(of: .grantTokenAccess).isEmpty)
  }

  @Test
  func revokingATokenSendsItsIDWithoutLookingItUp() async throws {
    let service = try service()

    let result = await service.run(["access", "revoke", "token:overlay", "--json"])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(try result.json()["closedConnections"] as? Int == 2)
    #expect(service.arguments(of: .getAccessStatus).isEmpty)
    let sent = try service.arguments(of: .revokeAccess).map {
      try JSONDecoder().decode(AccessRevokeArguments.self, from: $0)
    }
    #expect(sent.map(\.id) == ["token:overlay"])
  }

  @Test
  func webEnableNeedsForceAndAPortInRange() async throws {
    let service = try service()

    let refused = await service.run(["access", "web", "enable", "--no-input"])
    let low = await service.run(["access", "web", "enable", "--port", "80", "--force"])
    let enabled = await service.run([
      "access", "web", "enable", "--port", "48000", "--force", "--json",
    ])
    let disabled = await service.run(["access", "web", "disable", "--json"])

    #expect(refused.code == 64)
    #expect(low.code == 64)
    #expect(enabled.code == 0, "\(enabled.standardError)")
    #expect(try enabled.json()["listening"] as? Bool == true)
    #expect(try disabled.json()["enabled"] as? Bool == false)
    let sent = try service.arguments(of: .setWebAccess).map {
      try JSONDecoder().decode(AccessWebArguments.self, from: $0)
    }
    #expect(sent.map(\.enabled) == [true, false])
    #expect(sent.map(\.port) == [48_000, nil])
  }

  @Test
  func enableNeedsForceWithoutAPrompt() async throws {
    let service = try service()

    let refused = await service.run(["access", "enable", "--no-input"])
    let forced = await service.run(["access", "enable", "--force", "--json"])
    let disabled = await service.run(["access", "disable", "--json"])

    #expect(refused.code == 64)
    #expect(refused.standardError.contains("--force"))
    #expect(forced.code == 0, "\(forced.standardError)")
    #expect(try forced.json()["enabled"] as? Bool == true)
    #expect(try disabled.json()["enabled"] as? Bool == false)
    #expect(service.arguments(of: .setAccessEnabled).count == 2)
  }

  @Test
  func grantNeedsForceAndSendsTheSignatureOfTheClientID() async throws {
    let service = try service()

    let refused = await service.run(["access", "grant", Self.grant.id, "--no-input"])
    let granted = await service.run([
      "access", "grant", Self.grant.id, "--scope", "read", "--scope", "control", "--force",
      "--json",
    ])

    #expect(refused.code == 64)
    #expect(service.arguments(of: .grantAccess).count == 1)
    #expect(granted.code == 0, "\(granted.standardError)")
    #expect(try granted.json()["scopes"] as? [String] == ["read", "control"])
    let sent = try JSONDecoder().decode(
      AccessGrantArguments.self,
      from: try #require(service.arguments(of: .grantAccess).first)
    )
    #expect(sent.identity == Self.team)
    #expect(sent.path == Self.grant.path)
  }

  @Test
  func grantRefusesAnAdHocClientBeforeAnyRequest() async throws {
    let service = try service()
    let program = try Self.adHocProgram()
    defer { try? FileManager.default.removeItem(at: program.deletingLastPathComponent()) }

    let byPath = await service.run(["access", "grant", program.path, "--force"])
    let byID = await service.run(["access", "grant", Self.refused.id, "--force"])

    #expect(byPath.code == 1)
    #expect(byPath.standardError.contains("ad-hoc"))
    #expect(byID.code == 1)
    #expect(service.arguments(of: .grantAccess).isEmpty)
  }

  @Test
  func grantRejectsUnsignedFilesAndUnknownIDs() async throws {
    let service = try service()

    let unsigned = await service.run(["access", "grant", "/etc/hosts", "--force"])
    let unknown = await service.run(["access", "grant", "ffffffff", "--force"])

    #expect(unsigned.code == 1)
    #expect(unsigned.standardError.contains("/etc/hosts"))
    #expect(unknown.code == 1)
    #expect(unknown.standardError.contains("ojd access list"))
    #expect(service.arguments(of: .grantAccess).isEmpty)
  }

  @Test
  func revokeRemovesTheWholeGrantOrSomeScopes() async throws {
    let service = try service()

    let whole = await service.run(["access", "revoke", Self.grant.id, "--json"])
    let partial = await service.run([
      "access", "revoke", Self.grant.id, "--scope", "control", "--json",
    ])

    #expect(whole.code == 0, "\(whole.standardError)")
    #expect(try whole.json()["grant"] == nil)
    #expect(try whole.json()["closedConnections"] as? Int == 1)
    #expect((try partial.json()["grant"] as? [String: Any])?["scopes"] as? [String] == ["read"])
    let sent = try service.arguments(of: .revokeAccess).map {
      try JSONDecoder().decode(AccessRevokeArguments.self, from: $0)
    }
    #expect(sent.map(\.scopes) == [nil, [.control]])
  }

  /// A copy of `/usr/bin/true`, re-signed ad-hoc.
  private static func adHocProgram() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let program = directory.appendingPathComponent("tool")
    try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: program)
    let codesign = Process()
    codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    codesign.arguments = ["--force", "--sign", "-", program.path]
    codesign.standardError = FileHandle.nullDevice
    try codesign.run()
    codesign.waitUntilExit()
    #expect(codesign.terminationStatus == 0)
    return program
  }
}
