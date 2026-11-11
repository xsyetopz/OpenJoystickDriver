import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointListStreamTests {
  /// A client granted `scopes` that subscribed to `stream` with `members` after its welcome.
  private func subscribed(
    _ server: EndpointServer,
    scopes: [EndpointScope] = [.read],
    stream: String,
    members: String = ""
  ) async throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(EndpointFixture.tool, path: "/Tool", scopes: scopes)
    let client = try await EndpointTestClient(path: server.socketPath)
    let names = scopes.map { #""\#($0.rawValue)""# }.joined(separator: ",")
    await client.send(clientLine("Hello", #","scopes":[\#(names)]"#))
    #expect(try await client.readObject()["kind"] as? String == "Welcome")
    await client.send(clientLine("Subscription", #","stream":"\#(stream)"\#(members)"#))
    return client
  }

  /// The next line, which must satisfy the schema.
  private func schemaLine(_ client: EndpointTestClient) async throws -> [String: Any] {
    let line = try #require(await client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    return try client.object(line)
  }

  private func names(_ line: [String: Any], _ key: String) -> [String?] {
    (line[key] as? [[String: Any]] ?? []).map { $0["name"] as? String }
  }

  @Test
  func aProfilesSubscriptionSendsTheListAtOnceAndAgainOnlyWhenItChanges() async throws {
    let racing = FakeAutomation.profile("Racing")
    let automation = FakeAutomation(profiles: [racing])
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await subscribed(server, stream: "Profiles")
      let first = try await schemaLine(client)
      #expect(first["kind"] as? String == "Profiles")
      #expect(names(first, "profiles") == ["Racing"])
      #expect((first["profiles"] as? [[String: Any]])?.first?["isActive"] as? Bool == false)

      automation.replace(profiles: [racing], active: [racing.id])
      let activated = try await schemaLine(client)
      #expect((activated["profiles"] as? [[String: Any]])?.first?["isActive"] as? Bool == true)

      automation.replace(profiles: [racing, FakeAutomation.profile("Rally")], active: [racing.id])
      #expect(names(try await schemaLine(client), "profiles").count == 2)
    }
  }

  @Test
  func aProfilesSubscriptionOfNoProfilesSendsAnEmptyList() async throws {
    try await withEndpointServer { server, _ in
      let client = try await subscribed(server, stream: "Profiles")
      #expect((try await schemaLine(client)["profiles"] as? [Any])?.isEmpty == true)
    }
  }

  @Test
  func aModsSubscriptionSendsTheListAtOnceAndAgainAfterARemoval() async throws {
    let store = try EndpointModTests().store(holding: "arcade-pack")
    try await withEndpointServer(modStore: store) { server, _ in
      let client = try await subscribed(server, stream: "Mods")
      let first = try await schemaLine(client)
      #expect(first["kind"] as? String == "Mods")
      #expect(names(first, "mods") == ["arcade-pack"])

      try store.remove("arcade-pack")
      #expect(names(try await schemaLine(client), "mods").isEmpty)
    }
  }

  @Test
  func aListSubscriptionNeedsTheReadScope() async throws {
    for stream in ["Profiles", "Mods"] {
      try await withEndpointServer { server, _ in
        let client = try await subscribed(server, scopes: [.control], stream: stream)
        #expect(
          try await schemaLine(client)["code"] as? String == ErrorCode.notGranted.rawValue,
          "\(stream)"
        )
        #expect(await client.readLine() == nil, "\(stream)")
      }
    }
  }

  @Test
  func onlyTheControllersStreamTakesOutput() async throws {
    for stream in ["Profiles", "Mods"] {
      try await withEndpointServer { server, _ in
        let client = try await subscribed(server, stream: stream, members: #","output":true"#)
        #expect(
          try await schemaLine(client)["code"] as? String == ErrorCode.invalidMessage.rawValue,
          "\(stream)"
        )
        #expect(await client.readLine() == nil, "\(stream)")
      }
    }
  }

  @Test
  func aLineAfterAListSubscriptionEndsTheConnection() async throws {
    try await withEndpointServer { server, _ in
      let client = try await subscribed(server, stream: "Mods")
      #expect(try await schemaLine(client)["kind"] as? String == "Mods")
      await client.send(clientLine("ModList"))
      #expect(try await schemaLine(client)["code"] as? String == ErrorCode.unexpectedKind.rawValue)
    }
  }
}
