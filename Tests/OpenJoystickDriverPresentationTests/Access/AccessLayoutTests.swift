import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

struct AccessLayoutTests {
  private let signed = CodeSigningIdentity(
    kind: .signed,
    identifier: "com.example.app",
    publisherID: "ABCDE12345"
  )

  private func payload(
    grants: [AccessGrantSummary] = [],
    tokens: [AccessTokenSummary] = [],
    refused: [AccessRefusedClient] = [],
    refusedTokens: [AccessRefusedToken] = [],
    connections: [AccessConnection] = []
  ) -> AccessStatusPayload {
    AccessStatusPayload(
      enabled: true,
      socketPath: "/tmp/ojd.sock",
      connections: connections,
      grants: grants,
      refused: refused,
      web: AccessWebStatus(enabled: false, listening: false, port: nil, pagesPath: "/tmp/pages"),
      tokens: tokens,
      refusedTokens: refusedTokens
    )
  }

  @Test
  func emptyEndpointShowsNoList() {
    let layout = AccessLayout(payload())

    #expect(!layout.showsGrants)
    #expect(!layout.showsTokens)
    #expect(!layout.showsRefused)
    #expect(!layout.showsConnections)
  }

  @Test
  func eachListAppearsOnlyWithItems() {
    let grant = AccessGrantSummary(
      AccessGrant(identity: signed, scopes: [.read], grantedAt: "2026-01-01T00:00:00Z", path: "/a")
    )
    let token = AccessTokenSummary(name: "tool", origins: [], scopes: [.read], grantTime: "")
    let refused = AccessRefusedClient(
      identity: signed,
      path: "/a",
      scopes: [.read],
      reason: "E1002",
      refusalTime: "2026-01-01T00:00:00Z"
    )

    let grants = AccessLayout(payload(grants: [grant]))
    #expect(grants.showsGrants && !grants.showsTokens && !grants.showsRefused)
    let tokens = AccessLayout(payload(tokens: [token]))
    #expect(tokens.showsTokens && !tokens.showsGrants)
    #expect(AccessLayout(payload(refused: [refused])).showsRefused)
  }
}
