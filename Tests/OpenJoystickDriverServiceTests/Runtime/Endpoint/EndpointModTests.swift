import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized)
struct EndpointModTests {
  /// A client granted `scopes`, welcomed with them.
  private func welcomed(
    _ server: EndpointServer,
    scopes: [EndpointScope]
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

  /// A store that holds the package `name`, which holds one controller record.
  func store(holding name: String?) throws -> ModPackageStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-endpoint-mods-\(UUID().uuidString)",
      isDirectory: true
    )
    let store = ModPackageStore(
      directory: root.appendingPathComponent("Packages"),
      runningVersion: "0.6.0"
    )
    guard let name else { return store }
    let folder = root.appendingPathComponent("Staging/\(name)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let controllers = folder.appendingPathComponent("Controllers", isDirectory: true)
    try FileManager.default.createDirectory(at: controllers, withIntermediateDirectories: true)
    let record: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": "Controller", "vendorID": 0x1234,
      "productID": 0xABCD, "modes": [["id": "default", "protocol": ["family": "XboxGIP"]]],
    ]
    try PropertyListFixture.data(tree: record).write(
      to: controllers.appendingPathComponent("1234-abcd.plist")
    )
    let manifest: [String: Any] = [
      "apiVersion": OpenJoystickDriverAPI.version, "kind": ModPackageManifest.kind, "name": name,
      "version": "1.2.3", "author": "Tester", "requires": ["minimum": "0.6.0"],
      "controllers": ["1234-abcd.plist"],
    ]
    try PropertyListFixture.data(tree: manifest).write(
      to: folder.appendingPathComponent("mod.plist")
    )
    try store.install(folder)
    return store
  }

  @Test
  func modListAnswersInstalledPackagesAndConnectionStaysOpen() async throws {
    let store = try store(holding: "arcade-pack")
    try await withEndpointServer(modStore: store) { server, _ in
      let client = try await welcomed(server, scopes: [.read])

      await client.send(clientLine("ModList"))
      let mods = try await schemaLine(client)
      #expect(mods["kind"] as? String == "Mods")
      let entries = try #require(mods["mods"] as? [[String: Any]])
      #expect(entries.map { $0["name"] as? String } == ["arcade-pack"])
      #expect(entries.first?["version"] as? String == "1.2.3")
      #expect(entries.first?["author"] as? String == "Tester")

      await client.send(clientLine("ModList"))
      #expect(try await schemaLine(client)["kind"] as? String == "Mods")
    }
  }

  @Test
  func emptyStoreAnswersEmptyList() async throws {
    try await withEndpointServer(modStore: try store(holding: nil)) { server, _ in
      let client = try await welcomed(server, scopes: [.read])
      await client.send(clientLine("ModList"))
      #expect((try await schemaLine(client)["mods"] as? [Any])?.isEmpty == true)
    }
  }

  @Test
  func modListNeedsReadScopeAndNotControlScope() async throws {
    try await withEndpointServer { server, _ in
      let client = try await welcomed(server, scopes: [.control])
      await client.send(clientLine("ModList"))
      #expect(try await schemaLine(client)["code"] as? String == ErrorCode.notGranted.rawValue)
      #expect(await client.readLine() == nil)
    }
  }

  @Test
  func modListMayFollowProfileRequest() async throws {
    try await withEndpointServer(
      automation: FakeAutomation(profiles: [FakeAutomation.profile("Racing")])
    ) { server, _ in
      let client = try await welcomed(server, scopes: [.read, .control])
      await client.send(clientLine("ProfileRequest", #","action":"Activate","profile":"Racing""#))
      #expect(try await schemaLine(client)["kind"] as? String == "ProfileResult")
      await client.send(clientLine("ModList"))
      #expect(try await schemaLine(client)["kind"] as? String == "Mods")
    }
  }
}
