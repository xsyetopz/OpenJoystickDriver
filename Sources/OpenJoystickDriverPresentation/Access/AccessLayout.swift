import Foundation
import OpenJoystickDriverKit

/// Which lists of the Access form exist.
///
/// A list with nothing in it is left out; Grant and Create in the toolbar add the first item.
struct AccessLayout: Equatable {
  /// Whether the Grants list exists.
  let showsGrants: Bool
  /// Whether the Tokens list exists.
  let showsTokens: Bool
  /// Whether the list of refused clients and tokens exists.
  let showsRefused: Bool
  /// Whether the Connections list exists.
  let showsConnections: Bool

  /// Creates the layout for `status`.
  init(_ status: AccessStatusPayload) {
    showsGrants = !status.grants.isEmpty
    showsTokens = !status.tokens.isEmpty
    showsRefused = !status.refused.isEmpty || !status.refusedTokens.isEmpty
    showsConnections = !status.connections.isEmpty
  }
}
