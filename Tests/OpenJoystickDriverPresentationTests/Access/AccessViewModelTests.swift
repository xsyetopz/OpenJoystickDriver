import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

private final class FakeAccessService: AccessService, @unchecked Sendable {
  var payload = AccessStatusPayload(
    enabled: false,
    socketPath: "/tmp/ojd.sock",
    connections: [],
    grants: [],
    refused: [],
    web: AccessWebStatus(enabled: false, listening: false, port: nil, pagesPath: "/tmp/pages"),
    tokens: [],
    refusedTokens: []
  )
  var error: (any Error)?
  var calls: [String] = []
  var grantedScopes: [EndpointScope] = []

  func status() throws -> AccessStatusPayload {
    if let error { throw error }
    return payload
  }

  func setEnabled(_ enabled: Bool) throws -> AccessStatusPayload {
    calls.append("enabled:\(enabled)")
    return try status()
  }

  func setWeb(enabled: Bool, port: Int?) throws -> AccessStatusPayload {
    calls.append("web:\(enabled):\(port.map(String.init) ?? "-")")
    return try status()
  }

  func grant(
    _ identity: CodeSigningIdentity,
    path: String,
    scopes: [EndpointScope]
  ) -> AccessGrantSummary {
    calls.append("grant:\(identity.identifier)")
    grantedScopes = scopes
    return AccessGrantSummary(
      AccessGrant(identity: identity, scopes: scopes, grantedAt: "2026-01-01T00:00:00Z", path: path)
    )
  }

  func grantToken(
    name: String,
    origins: [String],
    scopes: [EndpointScope]
  ) -> AccessTokenGrantResult {
    calls.append("token:\(name)")
    return AccessTokenGrantResult(
      token: "secret",
      grant: AccessTokenSummary(
        name: name,
        origins: origins,
        scopes: scopes,
        grantTime: "2026-01-01T00:00:00Z"
      )
    )
  }

  func revoke(id: String, scopes: [EndpointScope]?) -> AccessRevokeResult {
    calls.append(
      "revoke:\(id):\(scopes.map { $0.map(\.rawValue).joined(separator: ",") } ?? "all")"
    )
    return AccessRevokeResult(id: id, grant: nil, token: nil, closedConnections: 0)
  }
}

@MainActor
struct AccessViewModelTests {
  private let signed = CodeSigningIdentity(
    kind: .signed,
    identifier: "com.example.app",
    publisherID: "ABCDE12345"
  )

  @Test
  func refreshLoadsTheStatus() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)

    await model.refresh()

    #expect(model.status?.socketPath == "/tmp/ojd.sock")
  }

  @Test
  func aServiceErrorThatStartsWithACodeKeepsThatCode() {
    let stale = AccessFailure(LocalServiceRPCError.remote("E5001: AccessGrants.plist is v1alpha2."))
    let unlabeled = AccessFailure(LocalServiceRPCError.remote("something broke"))

    #expect(stale.code == .unsupportedAPIVersion)
    #expect(stale.message == "E5001: AccessGrants.plist is v1alpha2.")
    #expect(unlabeled.code == .serviceRequestFailed)
  }

  @Test
  func aServiceThatIsNotRunningIsAnE2004Failure() async {
    let service = FakeAccessService()
    service.error = ApplicationServiceClientError.notConnected
    let model = AccessViewModel(service: service)

    await model.refresh()

    #expect(model.load == .failed(AccessFailure(ApplicationServiceClientError.notConnected)))
    #expect(AccessFailure(ApplicationServiceClientError.notConnected).code == .serviceUnavailable)
  }

  @Test
  func turningTheEndpointOnAsksFirst() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)

    model.requestEnableEndpoint()
    #expect(service.calls.isEmpty)
    #expect(model.sheet == .confirm(.enableEndpoint))
    await model.confirm(.enableEndpoint)

    #expect(service.calls == ["enabled:true"])
    #expect(model.sheet == nil)
  }

  @Test
  func turningTheEndpointOffNeedsNoConfirmation() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)

    await model.disableEndpoint()

    #expect(service.calls == ["enabled:false"])
  }

  @Test
  func aPortOutsideTheAllowedRangeIsRefused() {
    let model = AccessViewModel(service: FakeAccessService())
    model.portText = "80"

    model.requestEnableWeb()

    #expect(model.sheet == nil)
    #expect(model.failure?.code == .webPortUnavailable)
  }

  @Test
  func thePortFieldShowsTheSavedPort() async throws {
    let service = FakeAccessService()
    service.payload = AccessStatusPayload(
      enabled: false,
      socketPath: "/tmp/ojd.sock",
      connections: [],
      grants: [],
      refused: [],
      web: AccessWebStatus(enabled: false, listening: false, port: 43_210, pagesPath: "/tmp/p"),
      tokens: [],
      refusedTokens: []
    )
    let model = AccessViewModel(service: service)

    await model.refresh()

    #expect(model.portText == "43210")
    #expect(try model.webPort() == 43_210)
  }

  @Test
  func anEmptyPortKeepsTheSavedPort() async throws {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)

    model.requestEnableWeb()
    let port = try model.webPort()
    await model.confirm(.enableWeb(port: port))

    #expect(service.calls == ["web:true:-"])
  }

  private static func status(webPort: Int?) -> AccessStatusPayload {
    AccessStatusPayload(
      enabled: false,
      socketPath: "/tmp/ojd.sock",
      connections: [],
      grants: [],
      refused: [],
      web: AccessWebStatus(enabled: false, listening: false, port: webPort, pagesPath: "/tmp/p"),
      tokens: [],
      refusedTokens: []
    )
  }

  @Test
  func theEmptyPortFieldNamesTheSavedPort() async {
    let service = FakeAccessService()
    service.payload = Self.status(webPort: 43_210)
    let model = AccessViewModel(service: service)
    await model.refresh()

    model.portText = ""

    #expect(model.portPlaceholder == "43210")
    #expect(model.portPlaceholder != OJDLocalized.string("ui.access.web.port.automatic"))
  }

  @Test
  func choosingAutomaticAsksForAFreePortAndKeepsTheFieldEmpty() async throws {
    let service = FakeAccessService()
    service.payload = Self.status(webPort: 43_210)
    let model = AccessViewModel(service: service)
    await model.refresh()
    #expect(model.canChooseAutomaticPort)

    model.chooseAutomaticPort()
    await model.refresh()

    #expect(model.portText.isEmpty)
    #expect(model.portPlaceholder == OJDLocalized.string("ui.access.web.port.automatic"))
    #expect(!model.canChooseAutomaticPort)
    #expect(try model.webPort() == 0)
    model.requestEnableWeb()
    guard case .confirm(let pending)? = model.sheet else {
      Issue.record("no sheet")
      return
    }
    await model.confirm(pending)
    #expect(service.calls.last == "web:true:0")
  }

  @Test
  func typingAPortAfterChoosingAutomaticUsesThePort() throws {
    let model = AccessViewModel(service: FakeAccessService())
    model.chooseAutomaticPort()

    model.portText = "50000"

    #expect(try model.webPort() == 50_000)
  }

  @Test
  func noAutomaticChoiceIsOfferedWithoutASavedPort() async {
    let model = AccessViewModel(service: FakeAccessService())
    await model.refresh()

    #expect(!model.canChooseAutomaticPort)
  }

  @Test
  func theFieldFollowsTheSavedPortUntilTheUserEditsIt() async {
    let service = FakeAccessService()
    service.payload = Self.status(webPort: 43_210)
    let model = AccessViewModel(service: service)
    await model.refresh()
    service.payload = Self.status(webPort: 44_000)
    await model.refresh()
    #expect(model.portText == "44000")

    model.portText = "50000"
    service.payload = Self.status(webPort: 45_000)
    await model.refresh()

    #expect(model.portText == "50000")
  }

  @Test
  func anEditedEmptyFieldStaysEmptyOnRefresh() async {
    let service = FakeAccessService()
    service.payload = Self.status(webPort: 43_210)
    let model = AccessViewModel(service: service)
    await model.refresh()

    model.portText = ""
    await model.refresh()

    #expect(model.portText.isEmpty)
  }

  @Test
  func enablingWithAPortFollowsTheSavedPortAgain() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)
    await model.refresh()
    model.portText = "50000"
    service.payload = Self.status(webPort: 50_000)

    await model.confirm(.enableWeb(port: 50_000))
    service.payload = Self.status(webPort: 51_000)
    await model.refresh()

    #expect(model.portText == "51000")
  }

  @Test
  func grantingUsesTheChosenScopes() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)
    let candidate = AccessClientCandidate(identity: signed, path: "/Applications/App.app")

    model.requestGrant(candidate)
    model.grantScopes = [.read, .control]
    let confirmation = model.confirmation(for: .grantClient(candidate))
    await model.confirm(.grantClient(candidate))

    #expect(confirmation.lines.count == 2)
    #expect(service.grantedScopes == [.read, .control])
  }

  @Test
  func aPlatformClientGetsAWarningLine() {
    let model = AccessViewModel(service: FakeAccessService())
    let candidate = AccessClientCandidate(
      identity: CodeSigningIdentity(
        kind: .platform,
        identifier: "com.apple.tool",
        publisherID: nil
      ),
      path: "/usr/bin/tool"
    )

    #expect(model.confirmation(for: .grantClient(candidate)).lines.count == 2)
  }

  @Test
  func anAdHocClientCannotBeGranted() {
    let model = AccessViewModel(service: FakeAccessService())
    let candidate = AccessClientCandidate(
      identity: CodeSigningIdentity(kind: .adHoc, identifier: "tool", publisherID: nil),
      path: "/tmp/tool"
    )

    model.requestGrant(candidate)

    #expect(model.sheet == nil)
    #expect(model.failure?.code == .unsignedClient)
  }

  @Test
  func aProgramWithoutASignatureCannotBeGranted() {
    let model = AccessViewModel(service: FakeAccessService()) { _ in nil }

    model.requestGrant(programAt: URL(fileURLWithPath: "/tmp/tool"))

    #expect(model.sheet == nil)
    #expect(model.failure?.code == .unsignedClient)
  }

  @Test
  func aTokenForWebPagesCannotHaveTheControlScope() {
    let model = AccessViewModel(service: FakeAccessService())
    model.tokenDraft = AccessTokenDraft(
      name: "page",
      originsText: "https://example.com",
      scopes: [.read, .control]
    )

    model.requestGrantToken()

    #expect(model.sheet == nil)
    #expect(model.failure?.code == .controlScopeWithOrigins)
  }

  @Test
  func aTokenNeedsAName() {
    let model = AccessViewModel(service: FakeAccessService())
    model.tokenDraft = AccessTokenDraft(name: "  ", originsText: "", scopes: [.read])

    model.requestGrantToken()

    #expect(model.failure?.code == .invalidTokenName)
  }

  @Test
  func theIssuedTokenIsShownOnceAfterTheGrant() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)
    model.tokenDraft = AccessTokenDraft(name: "tool", originsText: "", scopes: [.read])
    model.requestGrantToken()

    await model.confirm(.grantToken(name: "tool", origins: []))

    #expect(model.sheet == .issuedToken(AccessIssuedToken(name: "tool", token: "secret")))
  }

  @Test
  func originsAreOnePerLineWithoutBlanks() {
    let draft = AccessTokenDraft(
      name: "page",
      originsText: "https://a.example\n\n  https://b.example  \n",
      scopes: [.read]
    )

    #expect(draft.origins == ["https://a.example", "https://b.example"])
  }

  @Test
  func revokingAsksThenRevokesById() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)
    let pending = AccessPending.revokeToken(id: "token:tool", name: "tool", scope: nil)

    model.requestRevoke(
      AccessTokenSummary(name: "tool", origins: [], scopes: [.read], grantTime: "")
    )
    #expect(model.sheet == .confirm(pending))
    #expect(model.confirmation(for: pending).isDestructive)
    await model.confirm(pending)

    #expect(service.calls == ["revoke:token:tool:all"])
  }

  @Test
  func revokingOneScopeAsksThenRevokesOnlyThatScope() async {
    let service = FakeAccessService()
    let model = AccessViewModel(service: service)
    let grant = AccessGrantSummary(
      AccessGrant(
        identity: signed,
        scopes: [.read, .control],
        grantedAt: "2026-01-01T00:00:00Z",
        path: "/Applications/Example.app"
      )
    )
    let pending = AccessPending.revokeGrant(
      id: grant.id,
      name: grant.identifier,
      scope: .control
    )

    model.requestRevoke(grant, scope: .control)
    #expect(model.sheet == .confirm(pending))
    #expect(
      model.confirmation(for: pending).lines.joined().contains(AccessPresentation.scope(.control))
    )
    #expect(model.confirmation(for: pending).isDestructive)
    await model.confirm(pending)

    #expect(service.calls == ["revoke:\(grant.id):Control"])
  }

  @Test
  func onlyAGrantWithSeveralScopesOffersToRevokeOne() {
    #expect(AccessViewModel.scopeChoices(of: [.read]).isEmpty)
    #expect(AccessViewModel.scopeChoices(of: [.read, .control]) == [.read, .control])
  }

  @Test
  func theWholeAndThePartialRevokeOfOneGrantAreDistinctSheets() {
    let whole = AccessPending.revokeGrant(id: "g", name: "g", scope: nil)
    let partial = AccessPending.revokeGrant(id: "g", name: "g", scope: .read)
    #expect(whole.id != partial.id)
  }

  @Test
  func aRefusedClientWithoutAPathIsNotGranted() {
    let model = AccessViewModel(service: FakeAccessService())
    let client = AccessRefusedClient(
      identity: signed,
      path: nil,
      scopes: [.read],
      reason: "E1002",
      refusalTime: "2026-01-01T00:00:00Z"
    )

    model.requestRefusedGrant(client)

    #expect(model.sheet == nil)
    #expect(model.failure?.code == .unsignedClient)
  }

  @Test
  func aRefusedClientWithAPathOpensTheGrantConfirmation() {
    let model = AccessViewModel(service: FakeAccessService())
    let client = AccessRefusedClient(
      identity: signed,
      path: "/usr/bin/tool",
      scopes: [.read],
      reason: "E1002",
      refusalTime: "2026-01-01T00:00:00Z"
    )

    model.requestRefusedGrant(client)

    #expect(
      model.sheet
        == .confirm(.grantClient(AccessClientCandidate(identity: signed, path: "/usr/bin/tool")))
    )
  }

  @Test
  func enablingTheWebEndpointWithoutAPortSaysItKeepsTheSavedPort() {
    let model = AccessViewModel(service: FakeAccessService())

    let lines = model.confirmation(for: .enableWeb(port: nil)).lines

    #expect(lines.count == 2)
    #expect(lines.allSatisfy { !$0.isEmpty })
  }

  @Test
  func enablingTheWebEndpointWithAnAutomaticPortSaysTheSystemPicksOne() {
    let model = AccessViewModel(service: FakeAccessService())

    let lines = model.confirmation(for: .enableWeb(port: 0)).lines

    #expect(lines.last == OJDLocalized.string("ui.access.web.enable.automatic"))
  }
}
