import Combine
import Foundation
import OpenJoystickDriverKit

/// A program that a grant names: its signature and where it was read.
struct AccessClientCandidate: Equatable, Identifiable {
  /// The program's code signature.
  let identity: CodeSigningIdentity
  /// Where the program was read.
  let path: String

  /// The signature's access identifier.
  var id: String { identity.accessID }
}

/// The input of the token form.
struct AccessTokenDraft: Equatable {
  /// The token's name.
  var name = ""
  /// One web origin per line; empty for a token that only local programs use.
  var originsText = ""
  /// The scopes that the token carries; read by default.
  var scopes: Set<EndpointScope> = [.read]

  /// The web origins in ``originsText``, one per non-empty line.
  var origins: [String] {
    originsText.split(whereSeparator: \.isNewline).map {
      $0.trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
  }
}

/// An operation that waits for the person's confirmation in a window-modal sheet.
enum AccessPending: Identifiable, Equatable {
  /// Enable the local endpoint.
  case enableEndpoint
  /// Enable the WebSocket on `port`; nil keeps the saved port and 0 asks for a free one.
  case enableWeb(port: Int?)
  /// Grant the program access.
  case grantClient(AccessClientCandidate)
  /// Create a token with the name for the web origins.
  case grantToken(name: String, origins: [String])
  /// `scope` nil removes the whole grant; otherwise only that scope.
  case revokeGrant(id: String, name: String, scope: EndpointScope?)
  /// Revoke a token, or only `scope` of it.
  case revokeToken(id: String, name: String, scope: EndpointScope?)

  /// The identity of the pending operation, which tells the sheets apart.
  var id: String {
    switch self {
    case .enableEndpoint: "enableEndpoint"
    case .enableWeb: "enableWeb"
    case .grantClient(let candidate): "grantClient.\(candidate.id)"
    case .grantToken(let name, _): "grantToken.\(name)"
    case .revokeGrant(let id, _, let scope): "revokeGrant.\(id).\(scope?.rawValue ?? "all")"
    case .revokeToken(let id, _, let scope): "revokeToken.\(id).\(scope?.rawValue ?? "all")"
    }
  }
}

/// The text and button of a confirmation sheet; its wording matches the action.
struct AccessConfirmation: Equatable {
  /// The sheet's title.
  let title: String
  /// The sheet's lines.
  let lines: [String]
  /// The title of the confirm button.
  let confirmTitle: String
  /// Whether the confirm button is marked destructive.
  let isDestructive: Bool
}

/// The token a grant created.
///
/// The service does not keep it, so the sheet that shows it is the only place it can be read.
struct AccessIssuedToken: Identifiable, Equatable {
  /// The token's name.
  let name: String
  /// The token's secret text.
  let token: String

  /// The identity of the token, which is its name.
  var id: String { name }
}

/// The sheet over the Access area.
enum AccessSheet: Identifiable, Equatable {
  /// The confirmation of a pending operation.
  case confirm(AccessPending)
  /// The form that creates a token.
  case tokenForm
  /// The sheet that shows a created token once.
  case issuedToken(AccessIssuedToken)

  /// The identity of the sheet, which tells the sheets apart.
  var id: String {
    switch self {
    case .confirm(let pending): "confirm.\(pending.id)"
    case .tokenForm: "tokenForm"
    case .issuedToken(let token): "issuedToken.\(token.id)"
    }
  }
}

/// The state and actions of the Access area: the service endpoint, the WebSocket, program grants
/// and tokens.
@MainActor
final class AccessViewModel: ObservableObject {
  /// The status of the Access area as loaded from the service.
  enum Load: Equatable {
    /// The status has not loaded yet.
    case loading
    /// The status as loaded.
    case loaded(AccessStatusPayload)
    /// The status could not be loaded.
    case failed(AccessFailure)
  }

  /// The status of the Access area.
  @Published
  private(set) var load = Load.loading
  /// Whether a request is running.
  @Published
  private(set) var busy = false
  /// Why the latest operation failed.
  @Published
  private(set) var failure: AccessFailure?
  /// The open sheet, or nil when none is open.
  @Published
  var sheet: AccessSheet?
  /// The scopes of the grant that the open confirmation sheet asks for.
  @Published
  var grantScopes: Set<EndpointScope> = [.read]
  /// The input of the token form.
  @Published
  var tokenDraft = AccessTokenDraft()
  /// The port field of the WebSocket form.
  ///
  /// It shows the saved port until the person edits it; empty keeps the saved port.
  @Published
  var portText = "" {
    didSet {
      guard !isFillingPort else { return }
      portEdited = true
      choosesAutomaticPort = false
    }
  }
  /// Whether enabling asks the system for a free port, whatever port is saved.
  @Published
  private(set) var choosesAutomaticPort = false

  /// Whether the person edited the port field, which stops it from following the saved port.
  private var portEdited = false
  /// Whether the model is filling the port field, which is not an edit by the person.
  private var isFillingPort = false
  /// Sends the access requests to the service.
  private let service: any AccessService
  /// Reads the code signature of the program at a path.
  private let identityAtPath: (URL) -> CodeSigningIdentity?

  /// Creates the model on a service and a signature reader.
  init(
    service: any AccessService = ApplicationServiceAccessService(),
    identityAtPath: @escaping (URL) -> CodeSigningIdentity? = {
      PlatformHosts.current.codeSigningIdentity(ofPath: $0)
    }
  ) {
    self.service = service
    self.identityAtPath = identityAtPath
  }

  /// The loaded status, or nil while it is loading or failed.
  var status: AccessStatusPayload? {
    if case .loaded(let status) = load { return status }
    return nil
  }

  /// The text the empty port field shows: the saved port that an empty field keeps, or
  /// "Automatic" when no port is saved or the person chose automatic.
  var portPlaceholder: String {
    if !choosesAutomaticPort, let port = status?.web.port { return String(port) }
    return OJDLocalized.string("ui.access.web.port.automatic")
  }

  /// Whether a port is saved that the person can replace with an automatic one.
  var canChooseAutomaticPort: Bool { status?.web.port != nil && !choosesAutomaticPort }

  /// Empties the field and makes enabling pick a free port instead of the saved one.
  func chooseAutomaticPort() {
    isFillingPort = true
    portText = ""
    isFillingPort = false
    portEdited = true
    choosesAutomaticPort = true
  }

  /// The port the field names: nil keeps the saved port, 0 asks for a free one.
  ///
  /// A failure names a port outside the range a user may bind.
  func webPort() throws -> Int? {
    if choosesAutomaticPort { return 0 }
    let text = portText.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    guard let port = Int(text), AccessWebPorts.allowed.contains(port) else {
      throw AccessFailure(
        message: OJDLocalized.formatted(
          "ui.access.web.portRange",
          AccessWebPorts.allowed.lowerBound,
          AccessWebPorts.allowed.upperBound
        ),
        code: .webPortUnavailable
      )
    }
    return port
  }

  /// Clears the failure message.
  func dismissFailure() { failure = nil }

  /// Loads the access status from the service.
  ///
  /// A failure shows in ``load``.
  func refresh() async {
    do { show(try await service.status()) } catch {
      load = .failed(AccessFailure(error))
    }
  }

  // MARK: Requests that need no confirmation

  /// Turns the local endpoint off.
  func disableEndpoint() async { await apply { try await service.setEnabled(false) } }

  /// Turns the WebSocket off.
  func disableWeb() async { await apply { try await service.setWeb(enabled: false, port: nil) } }

  // MARK: Requests that ask first

  /// Asks to confirm turning the local endpoint on.
  func requestEnableEndpoint() { sheet = .confirm(.enableEndpoint) }

  /// Asks to confirm turning the WebSocket on at the port that ``webPort()`` returns, or shows the
  /// failure for a port outside the allowed range.
  func requestEnableWeb() {
    perform {
      sheet = .confirm(.enableWeb(port: try webPort()))
    }
  }

  /// Asks to grant `candidate`, or shows a failure for a program with an ad hoc signature.
  func requestGrant(_ candidate: AccessClientCandidate) {
    guard candidate.identity.kind != .adHoc else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("ui.access.grant.adHoc", candidate.identity.identifier),
        code: .unsignedClient
      )
      return
    }
    grantScopes = [.read]
    sheet = .confirm(.grantClient(candidate))
  }

  /// Asks to grant the program at `url`.
  func requestGrant(programAt url: URL) {
    let url = url.standardizedFileURL
    guard let identity = identityAtPath(url) else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("ui.access.grant.unsigned", url.path),
        code: .unsignedClient
      )
      return
    }
    requestGrant(AccessClientCandidate(identity: identity, path: url.path))
  }

  /// Asks to grant a refused client.
  ///
  /// A client whose executable the service could not read has no path to record, so the grant is
  /// refused.
  func requestRefusedGrant(_ client: AccessRefusedClient) {
    guard let path = client.path else {
      failure = AccessFailure(
        message: OJDLocalized.formatted("ui.access.grant.noPath", client.identifier),
        code: .unsignedClient
      )
      return
    }
    requestGrant(AccessClientCandidate(identity: client.identity, path: path))
  }

  /// Opens the token form with an empty draft.
  func requestTokenForm() {
    tokenDraft = AccessTokenDraft()
    sheet = .tokenForm
  }

  /// Moves from the token form to its confirmation.
  func requestGrantToken() {
    let draft = tokenDraft
    guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty, !draft.scopes.isEmpty else {
      failure = AccessFailure(
        message: OJDLocalized.string("ui.access.token.incomplete"),
        code: .invalidTokenName
      )
      return
    }
    guard draft.origins.isEmpty || !draft.scopes.contains(.control) else {
      failure = AccessFailure(
        message: OJDLocalized.string("ui.access.token.originControl"),
        code: .controlScopeWithOrigins
      )
      return
    }
    sheet = .confirm(.grantToken(name: draft.name, origins: draft.origins))
  }

  /// The scopes of a grant that can be revoked one at a time.
  ///
  /// A grant with a single scope has none: revoking it removes the whole grant.
  static func scopeChoices(of scopes: [EndpointScope]) -> [EndpointScope] {
    scopes.count > 1 ? scopes : []
  }

  /// Asks to revoke `scope` of the grant, or the whole grant when `scope` is nil.
  func requestRevoke(_ grant: AccessGrantSummary, scope: EndpointScope? = nil) {
    sheet = .confirm(.revokeGrant(id: grant.id, name: grant.identifier, scope: scope))
  }

  /// Asks to revoke `scope` of the token, or the whole token when `scope` is nil.
  func requestRevoke(_ token: AccessTokenSummary, scope: EndpointScope? = nil) {
    sheet = .confirm(.revokeToken(id: token.id, name: token.name, scope: scope))
  }

  /// Closes the open sheet.
  func cancelSheet() { sheet = nil }

  /// Closes the sheet that shows the created token.
  func closeIssuedToken() { sheet = nil }

  /// Closes the sheet and runs the confirmed operation, then shows the status that follows.
  func confirm(_ pending: AccessPending) async {
    sheet = nil
    switch pending {
    case .enableEndpoint: await apply { try await service.setEnabled(true) }
    case .enableWeb(let port):
      await apply { try await service.setWeb(enabled: true, port: port) }
      if failure == nil, let status {
        portEdited = false
        choosesAutomaticPort = false
        show(status)
      }
    case .grantClient(let candidate):
      let scopes = grantScopes.sorted()
      await apply {
        _ = try await service.grant(candidate.identity, path: candidate.path, scopes: scopes)
        return try await service.status()
      }
    case .grantToken(let name, let origins):
      let scopes = tokenDraft.scopes.sorted()
      await apply {
        let result = try await service.grantToken(name: name, origins: origins, scopes: scopes)
        sheet = .issuedToken(AccessIssuedToken(name: result.grant.name, token: result.token))
        return try await service.status()
      }
    case .revokeGrant(let id, _, let scope), .revokeToken(let id, _, let scope):
      await apply {
        _ = try await service.revoke(id: id, scopes: scope.map { [$0] })
        return try await service.status()
      }
    }
  }

  // MARK: Confirmation text

  /// Returns the wording of the confirmation sheet for `pending`.
  func confirmation(for pending: AccessPending) -> AccessConfirmation {
    switch pending {
    case .enableEndpoint:
      return AccessConfirmation(
        title: OJDLocalized.string("ui.access.enable.title"),
        lines: [OJDLocalized.string("ui.access.enable.message")],
        confirmTitle: OJDLocalized.string("ui.access.enable"),
        isDestructive: false
      )
    case .enableWeb(let port):
      return AccessConfirmation(
        title: OJDLocalized.string("ui.access.web.enable.title"),
        lines: [
          OJDLocalized.string("platform.macos.ui.access.web.enable.message"),
          port.map {
            $0 == 0
              ? OJDLocalized.string("ui.access.web.enable.automatic")
              : OJDLocalized.formatted("ui.access.web.enable.port", $0)
          } ?? OJDLocalized.string("ui.access.web.enable.savedPort"),
        ],
        confirmTitle: OJDLocalized.string("ui.access.enable"),
        isDestructive: false
      )
    case .grantClient(let candidate):
      var lines: [String] = []
      if grantScopes.contains(.control) {
        lines.append(OJDLocalized.string("ui.access.grant.controlWarning"))
      }
      if candidate.identity.kind == .platform {
        lines.append(OJDLocalized.string("platform.macos.ui.access.grant.platformWarning"))
      }
      lines.append(
        OJDLocalized.formatted(
          "ui.access.grant.question",
          candidate.identity.identifier,
          AccessPresentation.signer(candidate.identity.kind, candidate.identity.publisherID),
          AccessPresentation.scopes(grantScopes.sorted())
        )
      )
      return AccessConfirmation(
        title: OJDLocalized.formatted("ui.access.grant.title", candidate.identity.identifier),
        lines: lines,
        confirmTitle: OJDLocalized.string("ui.access.grant"),
        isDestructive: false
      )
    case .grantToken(let name, let origins):
      var lines: [String] = []
      if tokenDraft.scopes.contains(.control) {
        lines.append(OJDLocalized.string("ui.access.grant.controlWarning"))
      }
      let scopes = AccessPresentation.scopes(tokenDraft.scopes.sorted())
      lines.append(
        origins.isEmpty
          ? OJDLocalized.formatted("ui.access.token.question", name, scopes)
          : OJDLocalized.formatted(
            "ui.access.token.webQuestion",
            name,
            scopes,
            origins.joined(separator: ", ")
          )
      )
      return AccessConfirmation(
        title: OJDLocalized.formatted("ui.access.token.title", name),
        lines: lines,
        confirmTitle: OJDLocalized.string("ui.access.grant"),
        isDestructive: false
      )
    case .revokeGrant(_, let name, let scope?):
      return partialRevoke(title: "ui.access.revoke.title", name: name, scope: scope)
    case .revokeToken(_, let name, let scope?):
      return partialRevoke(title: "ui.access.revokeToken.title", name: name, scope: scope)
    case .revokeGrant(_, let name, nil):
      return AccessConfirmation(
        title: OJDLocalized.formatted("ui.access.revoke.title", name),
        lines: [OJDLocalized.string("ui.access.revoke.message")],
        confirmTitle: OJDLocalized.string("ui.access.revoke"),
        isDestructive: true
      )
    case .revokeToken(_, let name, nil):
      return AccessConfirmation(
        title: OJDLocalized.formatted("ui.access.revokeToken.title", name),
        lines: [OJDLocalized.string("ui.access.revokeToken.message")],
        confirmTitle: OJDLocalized.string("ui.access.revoke"),
        isDestructive: true
      )
    }
  }

  /// Returns the confirmation for revoking only `scope`.
  private func partialRevoke(
    title: String,
    name: String,
    scope: EndpointScope
  )
    -> AccessConfirmation
  {
    AccessConfirmation(
      title: OJDLocalized.formatted(title, name),
      lines: [
        OJDLocalized.formatted("ui.access.revokeScope.message", AccessPresentation.scope(scope))
      ],
      confirmTitle: OJDLocalized.string("ui.access.revoke"),
      isDestructive: true
    )
  }

  // MARK: Private

  /// Clears the failure and runs `body`, which shows its error as the failure.
  private func perform(_ body: () throws -> Void) {
    failure = nil
    do { try body() } catch { failure = AccessFailure(error) }
  }

  /// Runs a request that returns the endpoint's state afterward, with ``busy`` set while it runs.
  private func apply(_ request: () async throws -> AccessStatusPayload) async {
    failure = nil
    busy = true
    defer { busy = false }
    do { show(try await request()) } catch { failure = AccessFailure(error) }
  }

  /// Loads `status` and, until the person edits the port field, fills it with the saved port.
  private func show(_ status: AccessStatusPayload) {
    load = .loaded(status)
    guard !portEdited else { return }
    isFillingPort = true
    portText = status.web.port.map(String.init) ?? ""
    isFillingPort = false
  }
}
