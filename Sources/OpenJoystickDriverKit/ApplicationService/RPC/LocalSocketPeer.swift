import Darwin
import Foundation

/// The process on the other end of a local socket, identified by its audit token.
///
/// The process identifier and the code both come from one audit token, so a process that exits
/// after it connects cannot hand its identifier to another process before the check.
public struct LocalSocketPeer: Sendable {
  /// The peer's process identifier, read from `auditToken`.
  public let processIdentifier: pid_t
  /// The peer's audit token.
  public let auditToken: audit_token_t

  /// Reads the peer of `descriptor`; nil when the peer runs as another user or has no token.
  public static func authenticated(_ descriptor: Int32) -> Self? {
    var userID: uid_t = 0
    var groupID: gid_t = 0
    guard getpeereid(descriptor, &userID, &groupID) == 0, userID == geteuid() else { return nil }
    var token = audit_token_t()
    var size = socklen_t(MemoryLayout<audit_token_t>.size)
    guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
      size == socklen_t(MemoryLayout<audit_token_t>.size)
    else { return nil }
    // `audit_token_to_pid` reads the same field; libbsm is not linked.
    let processIdentifier = pid_t(bitPattern: token.val.5)
    guard processIdentifier > 0 else { return nil }
    return Self(processIdentifier: processIdentifier, auditToken: token)
  }
}
