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
    reason: "not-granted",
    refusedAt: "2026-10-03T20:01:00Z"
  )

  /// A service with one grant and one refused client that answers each access method.
  private func service() throws -> FakeService {
    try FakeService(devices: []) { method, arguments in
      let status = { (enabled: Bool) in
        AccessStatusPayload(
          enabled: enabled,
          socketPath: "/tmp/endpoint.sock",
          connections: [AccessConnection(identity: Self.team, scopes: [.read])],
          grants: [Self.grant],
          refused: [Self.refused]
        )
      }
      switch method {
      case .getAccessStatus: return encoded(status(true))
      case .setAccessEnabled:
        let value = try? JSONDecoder().decode(AccessEnabledArguments.self, from: arguments)
        return encoded(status(value?.enabled ?? false))
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
    #expect(human.standardOutput.contains("/tmp/endpoint.sock"))
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
