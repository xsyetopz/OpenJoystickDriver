import CryptoKit

/// A connected controller that a ``ControllerReference`` can name.
public protocol ControllerReferenceable {
  /// The token of the controller's current attachment.
  var sessionToken: ControllerSessionToken { get }
  /// The controller's port key; nil when it has no location ID.
  var portKey: ControllerPortKey? { get }
  /// The controller's model.
  var model: ControllerModelID { get }
}

/// A connected controller's key with the token of its current attachment and its port key.
package struct ConnectedController: ControllerReferenceable, Hashable, Sendable {
  /// The controller's key.
  package let logicalControllerID: LogicalControllerID
  /// The token of the controller's current attachment.
  package let sessionToken: ControllerSessionToken
  /// The controller's port key under the installation key; nil when it has no location ID.
  package let portKey: ControllerPortKey?

  /// Creates the connected controller for `logicalControllerID` and derives its port key from
  /// `installationKey`.
  package init(
    logicalControllerID: LogicalControllerID,
    sessionToken: ControllerSessionToken,
    installationKey: SymmetricKey
  ) {
    self.logicalControllerID = logicalControllerID
    self.sessionToken = sessionToken
    self.portKey = ControllerPortKey.of(logicalControllerID, installationKey: installationKey)
  }

  /// The hardware model of the logical controller.
  package var model: ControllerModelID { logicalControllerID.model }
}

/// Why a ``ControllerReference`` names no single connected controller.
///
/// Both cases carry the catalog code ``ErrorCode/notFound`` (E2012).
public enum ControllerReferenceError: Error, Equatable, Sendable {
  /// No connected controller matches the reference.
  case notFound(ControllerReference)
  /// A model reference matches several connected controllers; name one by its session token or
  /// port key instead.
  case ambiguous(ControllerReference, matches: [ControllerSessionToken])

  /// The catalog code of every reference error.
  public var errorCode: ErrorCode { .notFound }
}

extension ControllerReference {
  /// Whether this reference names `controller`.
  public func names(_ controller: some ControllerReferenceable) -> Bool {
    switch self {
    case .session(let token): controller.sessionToken == token
    case .port(let portKey): controller.portKey == portKey
    case .model(let model): controller.model == model
    }
  }

  /// The controllers this reference names, in the order of `controllers`.
  public func matches<Controller: ControllerReferenceable>(
    in controllers: [Controller]
  ) -> [Controller] { controllers.filter(names) }

  /// The one controller in `controllers` this reference names.
  ///
  /// - Throws: ``ControllerReferenceError/notFound(_:)`` when none matches, and
  ///   ``ControllerReferenceError/ambiguous(_:matches:)`` with every match when several do.
  public func resolve<Controller: ControllerReferenceable>(
    in controllers: [Controller]
  ) throws(ControllerReferenceError) -> Controller {
    let matches = matches(in: controllers)
    guard let first = matches.first else { throw .notFound(self) }
    guard matches.count == 1 else { throw .ambiguous(self, matches: matches.map(\.sessionToken)) }
    return first
  }
}
