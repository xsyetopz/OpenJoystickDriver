import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct AccessGrantStoreTests {
  private let tool = CodeSigningIdentity(
    kind: .team,
    identifier: "com.example.tool",
    teamIdentifier: "ABCDE12345"
  )
  private let python = CodeSigningIdentity(
    kind: .apple,
    identifier: "com.apple.python3",
    teamIdentifier: nil
  )

  @Test
  func aMissingFileIsAnEndpointThatIsOffWithNoGrants() throws {
    try withStore { store, _ in
      let file = try store.load()
      #expect(file == AccessGrantFile())
    }
  }

  @Test
  func grantsRoundTripAndTheFileMatchesItsSchema() throws {
    try withStore { store, _ in
      var file = AccessGrantFile()
      file.enabled = true
      file.grant(
        tool,
        scopes: [.read],
        path: "/Applications/Tool.app",
        at: Date(timeIntervalSince1970: 0)
      )
      file.grant(
        python,
        scopes: [.read],
        path: "/usr/bin/python3",
        at: Date(timeIntervalSince1970: 0)
      )
      try store.save(file)

      #expect(try store.load() == file)
      let text = try String(contentsOf: store.url, encoding: .utf8)
      #expect(try JSONSchemaFiles.issues(in: text, against: "access-grants.schema.json").isEmpty)
      let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions]
      #expect(mode as? Int == 0o600)
    }
  }

  @Test
  func grantingAgainMergesScopesAndKeepsTheLatestPath() {
    var file = AccessGrantFile()
    file.grant(tool, scopes: [.control], path: "/old/Tool", at: Date(timeIntervalSince1970: 0))
    let grant = file.grant(
      tool,
      scopes: [.read],
      path: "/new/Tool",
      at: Date(timeIntervalSince1970: 60)
    )

    #expect(file.grants == [grant])
    #expect(grant.scopes == [.read, .control])
    #expect(grant.path == "/new/Tool")
    #expect(grant.grantedAt == "1970-01-01T00:01:00Z")
  }

  @Test
  func revokingSomeScopesKeepsTheRestAndRevokingAllRemovesTheGrant() throws {
    var file = AccessGrantFile()
    file.grant(tool, scopes: [.read, .control], path: "/Tool", at: Date())

    let remaining = try file.revoke(id: tool.accessID, scopes: [.control])
    #expect(remaining?.scopes == [.read])
    #expect(try file.revoke(id: tool.accessID, scopes: nil) == nil)
    #expect(file.grants.isEmpty)
    #expect(throws: AccessGrantStoreError.unknownClient("ffffffff")) {
      try file.revoke(id: "ffffffff", scopes: nil)
    }
  }

  @Test
  func aDamagedFileIsAnErrorAndIsNotReplaced() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for text in [
        "{",
        #"{"enabled":true,"grants":[{"kind":"ad-hoc","identifier":"a.out","scopes":["read"],"#
          + #""grantedAt":"x","path":"/a.out"}]}"#,
        #"{"enabled":true,"grants":[{"kind":"team","identifier":"x","scopes":["read"],"#
          + #""grantedAt":"x","path":"/x"}]}"#,
        #"{"enabled":true,"grants":[{"kind":"apple","identifier":"x","scopes":[],"#
          + #""grantedAt":"x","path":"/x"}]}"#,
      ] {
        try Data(text.utf8).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == text)
      }
    }
  }

  @Test
  func refusedClientsAreKeptForADay() {
    var log = AccessRefusalLog()
    let start = Date(timeIntervalSince1970: 0)
    log.record(tool, path: "/Tool", scopes: [.read], reason: "not-granted", at: start)
    log.record(python, path: nil, scopes: [.read], reason: "not-granted", at: start + 3_600)
    log.record(tool, path: "/Tool", scopes: [.control], reason: "not-granted", at: start + 7_200)

    #expect(log.clients(at: start + 7_200).map(\.id) == [tool.accessID, python.accessID])
    #expect(log.clients(at: start + 7_200).first?.scopes == [.control])
    #expect(log.clients(at: start + 3_600 + 86_401).map(\.id) == [tool.accessID])
    #expect(log.clients(at: start + 7_200 + 86_401).isEmpty)
  }

  private func withStore(_ body: (AccessGrantStore, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(AccessGrantStore(directory: directory), directory)
  }
}
