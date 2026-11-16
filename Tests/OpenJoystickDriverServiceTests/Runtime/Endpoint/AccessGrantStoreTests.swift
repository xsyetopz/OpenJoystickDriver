import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct AccessGrantStoreTests {
  private let tool = CodeSigningIdentity(
    kind: .signed,
    identifier: "com.example.tool",
    publisherID: "ABCDE12345"
  )
  private let python = CodeSigningIdentity(
    kind: .platform,
    identifier: "com.apple.python3",
    publisherID: nil
  )

  @Test
  func missingFileIsEndpointThatIsOffWithNoGrants() throws {
    try withStore { store, _ in
      let file = try store.load()
      #expect(file == AccessGrantFile())
    }
  }

  @Test
  func grantsRoundTripAndFileMatchesItsSchema() throws {
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
      #expect(
        try JSONSchemaFiles.issues(
          inPropertyList: Data(text.utf8),
          against: "access-grants.schema.json"
        )
        .isEmpty
      )
      let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions]
      #expect(mode as? Int == 0o600)
    }
  }

  @Test
  func grantingAgainMergesScopesAndKeepsLatestPath() {
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
  func revokingSomeScopesKeepsRestAndRevokingAllRemovesGrant() throws {
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
  func damagedFileIsErrorAndIsNotReplaced() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for text in [
        "{",
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
          + #""enabled":true,"grants":[{"publisher":{"kind":"AdHoc"},"identifier":"a.out","#
          + #""scopes":["Read"],"#
          + #""grantedAt":"x","path":"/a.out"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
          + #""enabled":true,"grants":[{"publisher":{"kind":"Signed"},"identifier":"x","#
          + #""scopes":["Read"],"#
          + #""grantedAt":"x","path":"/x"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
          + #""enabled":true,"grants":[{"publisher":{"kind":"Platform"},"identifier":"x","#
          + #""scopes":[],"#
          + #""grantedAt":"x","path":"/x"}],"tokens":[],"web":{"enabled":false,"port":47614}}"#,
      ] {
        try PropertyListFixture.bytes(json: text).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
        #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
      }
    }
  }

  @Test
  func damagedFileErrorCarriesItsCodeAndLocalizedText() {
    let message = AccessGrantStoreError.damaged.errorDescription ?? ""
    #expect(message == "E5005: \(ErrorCode.damagedAccessGrants.localizedExplanation)")
    #expect(message.contains(AccessGrantStore.fileName))
  }

  @Test(arguments: [
    #""publisher":{"kind":"x"},"identifier":"a.out""#,
    #""publisher":{"kind":"Signed","id":"ABCDE12345"},"identifier":"a.out","unexpected":1"#,
    #""publisher":{"kind":"Signed","id":"ABCDE12345","unexpected":1},"identifier":"a.out""#,
    #""publisher":{"kind":"Signed","id":"ABCDE12345"},"identifier":7"#,
    #""kind":"Signed","identifier":"a.out""#,
  ])
  func fileThatIsNotCurrentShapeIsDamagedAndLeftAsItWas(grant: String) throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let text =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":[{\#(grant),"#
        + #""scopes":["Read"],"grantedAt":"x","path":"/a.out"}],"tokens":[],"#
        + #""web":{"enabled":false,"port":47614}}"#
      try PropertyListFixture.bytes(json: text).write(to: store.url)

      #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
      #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
    }
  }

  @Test(arguments: [
    #""tokens":[],"web":{"enabled":false,"port":47614},"unexpected":1"#,
    #""tokens":[],"web":{"enabled":false,"port":47614,"unexpected":1}"#,
    #""tokens":[{"name":"overlay","tokenSHA256":"\#(String(repeating: "a", count: 64))","#
      + #""origins":[],"scopes":["Read"],"grantedAt":"x","unexpected":1}],"#
      + #""web":{"enabled":false,"port":47614}"#,
  ])
  func unknownKeyInFileTokensOrWebSettingsIsDamagedAndLeftAsItWas(rest: String) throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let text =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":[],"# + rest + "}"
      try PropertyListFixture.bytes(json: text).write(to: store.url)

      #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
      #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
    }
  }

  @Test
  func missingOrUnsupportedHeaderIsRefusedWithWhatWasFound() throws {
    let supported = "the supported apiVersion is \(OpenJoystickDriverAPI.version)"
    let body = #""enabled":true,"grants":[],"tokens":[],"web":{"enabled":false}}"#
    let cases: [(String, ErrorCode?, String)] = [
      (
        #"{"kind":"AccessGrants","# + body, .unsupportedAPIVersion,
        "no apiVersion found; \(supported)"
      ),
      (
        #"{"apiVersion":"unsupported.example/v9","kind":"AccessGrants","# + body,
        .unsupportedAPIVersion,
        "apiVersion unsupported.example/v9 is not supported; \(supported); "
          + "run `ojd migrate` to convert"
      ),
      (
        #"{"apiVersion":"openjoystickdriver/v1alpha1","kind":"AccessGrants","# + body,
        .unsupportedAPIVersion,
        "apiVersion openjoystickdriver/v1alpha1 is not supported; \(supported); "
          + "run `ojd migrate` to convert"
      ),
      (
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","# + body,
        nil, "no kind found; expected AccessGrants"
      ),
      (
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"Profile","# + body,
        nil, "expected AccessGrants, found Profile"
      ),
    ]
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for (text, code, reason) in cases {
        try PropertyListFixture.bytes(json: text).write(to: store.url)
        do {
          _ = try store.load()
          Issue.record("the header was accepted")
        } catch let AccessGrantStoreError.unsupported(problem) {
          #expect(problem.code == code)
          #expect(problem.message == "\(store.url.path): \(reason)")
          #expect(
            AccessGrantStoreError.unsupported(problem).code == code ?? .damagedAccessGrants
          )
        }
        #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
      }
    }
  }

  @Test
  func tokenGrantStoresOnlyHashOfItsToken() throws {
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
      #expect(
        try JSONSchemaFiles.issues(
          inPropertyList: Data(text.utf8),
          against: "access-grants.schema.json"
        )
        .isEmpty
      )
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
  func revokingTokenGrantByItsID() throws {
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
  func damagedTokenGrantOrWebSettingIsError() throws {
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
          #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
          + #""enabled":true,"grants":[],"tokens":[\#(tokens)],"#
          + #""web":{"enabled":false,"port":47614}}"#
        try PropertyListFixture.bytes(json: text).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged, "\(text)") { try store.load() }
      }
      for port in [0, 80, 70_000] {
        let text =
          #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
          + #""enabled":true,"grants":[],"tokens":[],"web":{"enabled":true,"port":\#(port)}}"#
        try PropertyListFixture.bytes(json: text).write(to: store.url)
        #expect(throws: AccessGrantStoreError.damaged, "\(text)") { try store.load() }
      }
      // The port is chosen at the first enable, so only a WebSocket that was never on lacks one.
      let off =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":[],"tokens":[],"web":{"enabled":false}}"#
      try PropertyListFixture.bytes(json: off).write(to: store.url)
      #expect(try store.load().web.port == nil)
      let on =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":[],"tokens":[],"web":{"enabled":true}}"#
      try PropertyListFixture.bytes(json: on).write(to: store.url)
      #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
    }
  }

  @Test
  func controlIsKeptWhenItWasGrantedAfterItWorked() throws {
    try withStore { store, _ in
      var file = AccessGrantFile()
      file.grant(tool, scopes: [.control], path: "/Tool", at: Date(timeIntervalSince1970: 0))
      try file.grantToken(name: "pad", origins: [], scopes: [.control], at: Date())
      try store.save(file)

      #expect(try store.load() == file)
      #expect(try store.load().grants.first?.scopes == [.control])
      #expect(try store.load().tokens.first?.scopes == [.control])
      let text = try String(contentsOf: store.url, encoding: .utf8)
      #expect(
        try JSONSchemaFiles.issues(
          inPropertyList: Data(text.utf8),
          against: "access-grants.schema.json"
        )
        .isEmpty
      )
    }
  }

  @Test
  func controlStoredBeforeItWorkedDamagesFileAndIsNeverHonored() throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let hash = String(repeating: "a", count: 64)
      func grant(_ scopes: String) -> String {
        #"{"publisher":{"kind":"Platform"},"identifier":"x","scopes":\#(scopes),"#
          + #""grantedAt":"1970-01-01T00:00:00Z","path":"/x"}"#
      }
      func token(_ scopes: String) -> String {
        #"{"name":"pad","tokenSHA256":"\#(hash)","origins":[],"scopes":\#(scopes),"#
          + #""grantedAt":"1970-01-01T00:00:00Z"}"#
      }
      for scopes in [#"["Control"]"#, #"["Read","Control"]"#] {
        for (grants, tokens) in [(grant(scopes), ""), ("", token(scopes))] {
          let text =
            #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","#
            + #""kind":"\#(AccessGrantFile.kind)","enabled":true,"grants":[\#(grants)],"#
            + #""tokens":[\#(tokens)],"#
            + #""web":{"enabled":false}}"#
          #expect(
            !(try JSONSchemaFiles.issues(in: text, against: "access-grants.schema.json").isEmpty),
            "\(text)"
          )
          try PropertyListFixture.bytes(json: text).write(to: store.url)
          #expect(throws: AccessGrantStoreError.damaged, "\(text)") { try store.load() }
          #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
        }
      }
      // Without `control`, the same grants load as they are.
      let text =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":["#
        + grant(#"["Read"]"#) + #"],"tokens":["#
        + token(#"["Read"]"#) + #"],"web":{"enabled":false}}"#
      try PropertyListFixture.bytes(json: text).write(to: store.url)
      let file = try store.load()
      #expect(file.grants.first?.scopes == [.read])
      #expect(file.tokens.first?.scopes == [.read])
    }
  }

  @Test
  func tokenWithOriginsCannotHoldControl() {
    var file = AccessGrantFile()
    #expect(throws: AccessGrantStoreError.originsWithControl) {
      try file.grantToken(
        name: "pad",
        origins: ["http://localhost:8080"],
        scopes: [.read, .control],
        at: Date()
      )
    }
    #expect(file.tokens.isEmpty)
  }

  @Test(arguments: [#"["read","control"]"#, #"["control"]"#])
  func tokenWithOriginsHoldingControlIsDamagedAndLeftAsItWas(scopes: String) throws {
    try withStore { store, directory in
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let text =
        #"{"apiVersion":"\#(OpenJoystickDriverAPI.version)","kind":"\#(AccessGrantFile.kind)","#
        + #""enabled":true,"grants":[],"tokens":[{"name":"page","#
        + #""tokenSHA256":"\#(String(repeating: "a", count: 64))","#
        + #""origins":["http://localhost:8080"],"scopes":\#(scopes),"#
        + #""grantedAt":"1970-01-01T00:00:00Z","controlGrantedAt":"1970-01-01T00:00:00Z"}],"#
        + #""web":{"enabled":false}}"#
      try PropertyListFixture.bytes(json: text).write(to: store.url)

      #expect(throws: AccessGrantStoreError.damaged) { try store.load() }
      #expect(try Data(contentsOf: store.url) == PropertyListFixture.bytes(json: text))
    }
  }

  @Test
  func refusedTokensAreKeptForDayByNameOriginAndTransport() {
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
  func refusedClientsAreKeptForDay() {
    var log = AccessRefusalLog()
    let start = Date(timeIntervalSince1970: 0)
    log.record(tool, path: "/Tool", scopes: [.read], at: start)
    log.record(python, path: nil, scopes: [.read], at: start + 3_600)
    log.record(tool, path: "/Tool", scopes: [.control], at: start + 7_200)

    #expect(log.clients(at: start + 7_200).map(\.id) == [tool.accessID, python.accessID])
    #expect(log.clients(at: start + 7_200).first?.scopes == [.control])
    #expect(log.clients(at: start + 7_200).first?.reason == "E1002")
    #expect(log.clients(at: start + 3_600 + 86_401).map(\.id) == [tool.accessID])
    #expect(log.clients(at: start + 7_200 + 86_401).isEmpty)
  }

  /// The Python reference client checks its proof against the same vector.
  @Test
  func tokenAcceptsSharedProofVector() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // Endpoint
      .deletingLastPathComponent()  // Runtime
      .deletingLastPathComponent()  // OpenJoystickDriverServiceTests
      .deletingLastPathComponent()  // Tests
      .appendingPathComponent("RepositoryScripts/fixtures/endpoint_hello_proof.json")
    let vector = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    let token = try #require(vector["token"])
    let nonce = try #require(vector["nonce"])
    let proof = try #require(vector["proof"])
    let grant = AccessTokenGrant(
      name: "reference",
      tokenSHA256: AccessTokenGrant.hash(token),
      origins: [],
      scopes: [.control],
      grantedAt: "2026-10-05T00:00:00Z"
    )

    #expect(grant.accepts(proof: proof, nonce: nonce, origin: "", port: ""))
    #expect(!grant.accepts(proof: proof, nonce: nonce + "x", origin: "", port: ""))
    #expect(tokenHello(name: "reference", token: token, nonce: nonce).contains(proof))
  }

  private func withStore(_ body: (AccessGrantStore, URL) throws -> Void) throws {
    let directory = MacOSDataDirectory().url(for: .temporary).appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(AccessGrantStore(directory: directory), directory)
  }
}
