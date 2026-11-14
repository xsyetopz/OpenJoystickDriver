import Foundation
import OpenJoystickDriverKit

/// Words for the values of the access payloads.
enum AccessPresentation {
  /// A client's program or folder path, with the home folder written as `~`.
  static func location(_ path: String) -> String { HomeFolder.redacting(path) }

  /// Returns the localized names of `scopes`, joined with commas.
  static func scopes(_ scopes: [EndpointScope]) -> String {
    scopes.map(scope).joined(separator: ", ")
  }

  /// Returns the localized name of the scope.
  static func scope(_ scope: EndpointScope) -> String {
    switch scope {
    case .read: OJDLocalized.string("ui.access.scope.read")
    case .control: OJDLocalized.string("ui.access.scope.control")
    }
  }

  /// The tooltip of the toggle of a scope: what the scope lets a program do.
  static func scopeHelp(_ scope: EndpointScope) -> String {
    switch scope {
    case .read: OJDLocalized.string("ui.help.scopeRead")
    case .control: OJDLocalized.string("ui.help.scopeControl")
    }
  }

  /// How a client was signed, with the publisher's ID for a signed one.
  static func signer(_ kind: CodeSigningIdentity.Kind, _ publisherID: String?) -> String {
    switch kind {
    case .signed:
      publisherID.map { OJDLocalized.formatted("ui.access.signer.signed", $0) }
        ?? OJDLocalized.string("ui.access.signer.signedUnknownPublisher")
    case .platform: OJDLocalized.string("platform.macos.ui.access.signer.platform")
    case .adHoc: OJDLocalized.string("ui.access.signer.adHoc")
    }
  }

  /// Returns the localized name of the way a client connects.
  static func transport(_ transport: AccessTransport) -> String {
    switch transport {
    case .socket: OJDLocalized.string("ui.access.transport.socket")
    case .web: OJDLocalized.string("ui.access.transport.web")
    }
  }

  /// The state of the WebSocket in a sentence.
  static func web(_ web: AccessWebStatus) -> String {
    guard web.enabled else { return OJDLocalized.string("ui.access.web.off") }
    guard let port = web.port, let url = web.url, let pagesURL = web.pagesURL else {
      return OJDLocalized.string("ui.access.web.noPort")
    }
    guard web.listening else { return OJDLocalized.formatted("ui.access.web.closed", String(port)) }
    return OJDLocalized.formatted("ui.access.web.on", url, pagesURL)
  }
}
