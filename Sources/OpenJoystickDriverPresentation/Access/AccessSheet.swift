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
