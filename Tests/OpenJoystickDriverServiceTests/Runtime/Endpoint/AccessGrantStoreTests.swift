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
          + #""grantedAt":"x","path":"/a.out"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
        #"{"enabled":true,"grants":[{"kind":"team","identifier":"x","scopes":["read"],"#
          + #""grantedAt":"x","path":"/x"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
        #"{"enabled":true,"grants":[{"kind":"apple","identifier":"x","scopes":[],"#
          + #""grantedAt":"x","path":"/x"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
      ] {
        try Data(text.utf8).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == text)
      }
    }
  }

  @Test
  func aTokenGrantStoresOnlyTheHashOfItsToken() throws {
    try withStore { store, _ in
      var file = AccessGrantFile()
      let (token, grant) = try file.grantToken(
        name: "overlay",
        origins: ["http://127.0.0.1:47614"],
        scopes: [.read],
        at: Date(timeIntervalSince1970: 0)
      )
      try store.save(file)

      #expect(token.hasPrefix("ojd_"))
      #expect(token.count == 47)
      #expect(grant.id == "token:overlay")
      #expect(try store.load() == file)
      #expect(try store.load().tokens == [grant])
      #expect(grant.tokenSHA256 == AccessTokenGrant.hash(token))
      let text = try String(contentsOf: store.url, encoding: .utf8)
      #expect(!text.contains(token))
      #expect(text.contains(grant.tokenSHA256))
      #expect(try JSONSchemaFiles.issues(in: text, against: "access-grants.schema.json").isEmpty)
    }
  }

  @Test
  func tokenNamesAreUniqueAndValidated() throws {
    var file = AccessGrantFile()
    try file.grantToken(name: "overlay", origins: [], scopes: [.read], at: Date())

    #expect(throws: AccessGrantStoreError.duplicateToken("overlay")) {
      try file.grantToken(name: "overlay", origins: [], scopes: [.read], at: Date())
    }
    for name in ["", "a b", "token:x", String(repeating: "a", count: 65)] {
      #expect(throws: AccessGrantStoreError.invalidTokenName(name)) {
        try file.grantToken(name: name, origins: [], scopes: [.read], at: Date())
      }
    }
    #expect(throws: AccessGrantStoreError.noScope) {
      try file.grantToken(name: "empty", origins: [], scopes: [], at: Date())
    }
  }

  @Test(arguments: [
    ("HTTP://LocalHost:8080/", "http://localhost:8080"),
    ("https://overlay.example:443", "https://overlay.example"),
    ("http://127.0.0.1:80", "http://127.0.0.1"),
    ("http://127.0.0.1:47614", "http://127.0.0.1:47614"),
  ])
  func originsAreStoredAsSchemeHostAndPort(origin: String, stored: String) throws {
    var file = AccessGrantFile()
    let (_, grant) = try file.grantToken(
      name: "overlay",
      origins: [origin, stored],
      scopes: [.read],
      at: Date()
    )
    #expect(grant.origins == [stored])
  }

  @Test(arguments: [
    "null", "file:///Users/me/overlay.html", "http://example.com/overlay", "ws://localhost:1",
    "http://user@example.com", "http://example.com?x", "example.com", "",
  ])
  func originsThatAreNotWebOriginsAreRefused(origin: String) {
    var file = AccessGrantFile()
    #expect(throws: AccessGrantStoreError.invalidOrigin(origin)) {
      try file.grantToken(name: "overlay", origins: [origin], scopes: [.read], at: Date())
    }
  }

  @Test
  func revokingATokenGrantByItsID() throws {
    var file = AccessGrantFile()
    try file.grantToken(name: "overlay", origins: [], scopes: [.read, .control], at: Date())

    #expect(try file.revokeToken(id: "token:overlay", scopes: [.control])?.scopes == [.read])
    #expect(try file.revokeToken(id: "token:overlay", scopes: nil) == nil)
    #expect(file.tokens.isEmpty)
    #expect(throws: AccessGrantStoreError.unknownClient("token:overlay")) {
      try file.revokeToken(id: "token:overlay", scopes: nil)
    }
  }

  @Test
  func aDamagedTokenGrantOrWebSettingIsAnError() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let hash = String(repeating: "a", count: 64)
      func token(_ name: String, _ hash: String, _ origins: String, _ scopes: String) -> String {
        #"{"name":"\#(name)","tokenSHA256":"\#(hash)","origins":\#(origins),"#
          + #""scopes":\#(scopes),"grantedAt":"x"}"#
      }
      for tokens in [
        token("a b", hash, "[]", #"["read"]"#),
        token("overlay", "abc", "[]", #"["read"]"#),
        token("overlay", hash, #"["null"]"#, #"["read"]"#),
        token("overlay", hash, #"["HTTP://x"]"#, #"["read"]"#),
        token("overlay", hash, "[]", "[]"),
        token("overlay", hash, "[]", #"["read"]"#) + ","
          + token("overlay", hash, "[]", #"["read"]"#),
      ] {
        let text =
          #"{"enabled":true,"grants":[],"tokens":[\#(tokens)],"#
          + #""web":{"enabled":false,"port":47614}}"#
        try Data(text.utf8).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged, "\(text)") { try store.load() }
      }
      for port in [0, 80, 70_000] {
        let text =
          #"{"enabled":true,"grants":[],"tokens":[],"web":{"enabled":true,"port":\#(port)}}"#
        try Data(text.utf8).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged, "\(text)") { try store.load() }
      }
      // The port is chosen at the first enable, so only a WebSocket that was never on lacks one.
      let off = #"{"enabled":true,"grants":[],"tokens":[],"web":{"enabled":false}}"#
      try Data(off.utf8).write(to: store.url)
      #expect(try store.load().web.port == nil)
      let on = #"{"enabled":true,"grants":[],"tokens":[],"web":{"enabled":true}}"#
      try Data(on.utf8).write(to: store.url)
      #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
    }
  }

  @Test
  func refusedTokensAreKeptForADayByNameOriginAndTransport() {
    var log = AccessRefusalLog()
    let start = Date(timeIntervalSince1970: 0)
    log.recordToken(name: nil, origin: nil, transport: .socket, scopes: [.read], at: start)
    log.recordToken(
      name: "overlay",
      origin: "http://evil.example",
      transport: .web,
      scopes: [.read],
      at: start + 60
    )
    log.recordToken(name: nil, origin: nil, transport: .socket, scopes: [.read], at: start + 120)

    let tokens = log.tokens(at: start + 120)
    #expect(tokens.map(\.name) == [nil, "overlay"])
    #expect(tokens.map(\.transport) == [.socket, .web])
    #expect(tokens.last?.origin == "http://evil.example")
    #expect(log.tokens(at: start + 120 + 86_401).isEmpty)
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
