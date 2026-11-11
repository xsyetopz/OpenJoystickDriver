import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointProfileTests {
  /// A client granted `scopes`, welcomed with them.
  private func welcomed(
    _ server: EndpointServer,
    scopes: [EndpointScope] = [.control]
  ) async throws -> EndpointTestClient {
    try server.setEnabled(true)
    try server.grant(EndpointFixture.tool, path: "/Tool", scopes: scopes)
    let client = try await EndpointTestClient(path: server.socketPath)
    let names = scopes.map { #""\#($0.rawValue)""# }.joined(separator: ",")
    await client.send(clientLine("Hello", #","scopes":[\#(names)]"#))
    #expect(try await client.readObject()["kind"] as? String == "Welcome")
    return client
  }

  /// The next line, which must satisfy the schema.
  private func schemaLine(_ client: EndpointTestClient) async throws -> [String: Any] {
    let line = try #require(await client.readLine())
    #expect(try JSONSchemaFiles.issues(in: line, against: "endpoint.schema.json").isEmpty)
    return try client.object(line)
  }

  @Test
  func aProfileRequestActivatesAndDeactivatesAProfileByName() async throws {
    let racing = FakeAutomation.profile("Racing")
    try await withEndpointServer(automation: FakeAutomation(profiles: [racing])) { server, _ in
      let client = try await welcomed(server)

      await client.send(
        clientLine("ProfileRequest", #","action":"Activate","profile":"racing""#)
      )
      let activated = try await schemaLine(client)
      let profile = try #require(activated["profile"] as? [String: Any])
      #expect(activated["kind"] as? String == "ProfileResult")
      #expect(profile["id"] as? String == racing.id.uuidString)
      #expect(profile["isActive"] as? Bool == true)

      await client.send(
        clientLine("ProfileRequest", #","action":"Deactivate","profile":"\#(racing.id)""#)
      )
      let deactivated = try await schemaLine(client)
      #expect((deactivated["profile"] as? [String: Any])?["isActive"] as? Bool == false)
    }
  }

  @Test
  func aProfileRequestSetsOneValueAndTheConnectionStaysOpen() async throws {
    let racing = FakeAutomation.profile("Racing")
    let automation = FakeAutomation(profiles: [racing])
    try await withEndpointServer(automation: automation) { server, _ in
      let client = try await welcomed(server)

      await client.send(
        clientLine(
          "ProfileRequest",
          #","action":"Set","profile":"Racing","key":"name","value":"Rally""#
        )
      )
      let renamed = try await schemaLine(client)
      #expect((renamed["profile"] as? [String: Any])?["name"] as? String == "Rally")
      #expect(automation.getRemappingSnapshot().profiles.map(\.name) == ["Rally"])

      await client.send(
        clientLine("ProfileRequest", #","action":"Activate","profile":"Rally""#)
      )
      #expect(try await schemaLine(client)["kind"] as? String == "ProfileResult")
    }
  }

  @Test
  func aRefusedRequestAnswersWithTheCodeOfOjdAndKeepsTheConnectionOpen() async throws {
    let racing = FakeAutomation.profile("Racing")
    try await withEndpointServer(automation: FakeAutomation(profiles: [racing])) { server, _ in
      let client = try await welcomed(server)

      await client.send(clientLine("ProfileRequest", #","action":"Activate","profile":"Menus""#))
      let missing = try await schemaLine(client)
      #expect(missing["kind"] as? String == "Status")
      #expect(missing["code"] as? String == ErrorCode.notFound.rawValue)

      await client.send(
        clientLine(
          "ProfileRequest",
          #","action":"Set","profile":"Racing","key":"name","value":null"#
        )
      )
      let removed = try await schemaLine(client)
      #expect(removed["kind"] as? String == "Status")
      #expect(removed["code"] as? String == ErrorCode.invalidProfile.rawValue)

      await client.send(clientLine("ProfileRequest", #","action":"Activate","profile":"Racing""#))
      #expect(try await schemaLine(client)["kind"] as? String == "ProfileResult")
    }
  }

  @Test
  func aSetWithoutAKeyOrAValueEndsTheConnection() async throws {
    try await withEndpointServer(
      automation: FakeAutomation(profiles: [FakeAutomation.profile("Racing")])
    ) { server, _ in
      for fields in [
        #","action":"Set","profile":"Racing","value":1"#,
        #","action":"Set","profile":"Racing","key":"name""#,
        #","action":"Set","profile":"Racing","key":"a..b","value":1"#,
        #","action":"Set","profile":"","key":"name","value":"x""#,
        #","action":"Jump","profile":"Racing""#,
      ] {
        let client = try await welcomed(server)
        await client.send(clientLine("ProfileRequest", fields))
        #expect(try await schemaLine(client)["code"] as? String == "E1003")
        #expect(await client.readLine() == nil)
      }
    }
  }

  @Test
  func aProfileRequestNeedsTheControlScope() async throws {
    try await withEndpointServer(
      automation: FakeAutomation(profiles: [FakeAutomation.profile("Racing")])
    ) { server, _ in
      let client = try await welcomed(server, scopes: [.read])
      await client.send(clientLine("ProfileRequest", #","action":"Activate","profile":"Racing""#))
      #expect(try await schemaLine(client)["code"] as? String == ErrorCode.notGranted.rawValue)
      #expect(await client.readLine() == nil)
    }
  }
}
