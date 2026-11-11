import Darwin
import Foundation
import Testing

/// The suites that open listening sockets.
///
/// The scan sees every socket of the process, so these suites run one test at a time.
@Suite(.serialized)
enum ListeningSocketSuites {}

/// Lists the sockets of this process that are in the listening state (`SO_ACCEPTCONN`).
///
/// It scans the descriptors of the process for sockets of any family, with no external tool.
enum ListeningSockets {
  /// The listening sockets of this process, each as `fd <number> family <number>`.
  static func ofThisProcess() -> [String] {
    let pid = getpid()
    let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
    guard bytes > 0 else { return [] }
    var descriptors = [proc_fdinfo](
      repeating: proc_fdinfo(),
      count: Int(bytes) / MemoryLayout<proc_fdinfo>.size
    )
    let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, bytes)
    let count = Int(filled) / MemoryLayout<proc_fdinfo>.size
    var found: [String] = []
    for descriptor in descriptors.prefix(count)
    where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
      var info = socket_fdinfo()
      let size = proc_pidfdinfo(
        pid,
        descriptor.proc_fd,
        PROC_PIDFDSOCKETINFO,
        &info,
        Int32(MemoryLayout<socket_fdinfo>.size)
      )
      guard size == MemoryLayout<socket_fdinfo>.size else { continue }
      if info.psi.soi_options & Int16(SO_ACCEPTCONN) != 0 {
        found.append("fd \(descriptor.proc_fd) family \(info.psi.soi_family)")
      }
    }
    return found
  }
}
