import Darwin
import Foundation
import OpenJoystickDriverKit

/// A listening socket, and the pipe that wakes the loop accepting on it.
///
/// The accept loop owns the descriptor and closes it (`finish`) when it ends, so the descriptor's
/// number cannot belong to a later listener while the loop still runs. `wake` closes the pipe's
/// write end, which makes the read end readable and ends the loop, and replaces the socket under
/// the descriptor's number with the placeholder (an open `/dev/null`), so the address is free for
/// the next listener at once while the number stays taken.
final class AcceptListener: @unchecked Sendable {
  /// The listening socket.
  let descriptor: Int32
  /// The TCP port, or 0 for a Unix socket.
  let port: Int
  /// The read end of the wake pipe; it hangs up when `wake` runs.
  let wakeRead: Int32
  /// The write end of the wake pipe.
  private let wakeWrite: Int32
  /// Takes one connection from `descriptor`, as `accept` does; tests replace it to fail the call.
  private let acceptCall: @Sendable (Int32) -> Int32
  /// The lock that guards the descriptors.
  private let lock = NSLock()
  /// The open `/dev/null` that replaces the socket when the listener is woken, or -1 once closed.
  private var placeholder: Int32
  /// Whether the wake pipe's write end is open.
  private var wakeWriteOpen = true
  /// Whether the listening socket is open.
  private var descriptorOpen = true

  /// What the accept loop is waiting for.
  enum Wait: Equatable {
    /// A connection is waiting.
    case ready
    /// The listener was stopped or replaced.
    case woken
    /// `poll` failed or the listener is broken; the error says why.
    case failed(Int32)
  }

  /// Takes over `descriptor`, which must be listening, and closes it when this throws.
  init(
    listening descriptor: Int32,
    port: Int = 0,
    acceptCall: @escaping @Sendable (Int32) -> Int32 = { Darwin.accept($0, nil, nil) }
  ) throws {
    var opened: [Int32] = []
    do {
      let flags = fcntl(descriptor, F_GETFL)
      guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
        throw LocalServiceRPCError.connectionFailed(errno)
      }
      var pipeEnds: [Int32] = [-1, -1]
      guard unsafe pipe(&pipeEnds) == 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      opened = pipeEnds
      let reserved = unsafe open("/dev/null", O_RDONLY)
      guard reserved >= 0 else { throw LocalServiceRPCError.connectionFailed(errno) }
      opened.append(reserved)
      for end in opened {
        guard fcntl(end, F_SETFD, FD_CLOEXEC) == 0 else {
          throw LocalServiceRPCError.connectionFailed(errno)
        }
      }
    } catch {
      for end in opened { Darwin.close(end) }
      Darwin.close(descriptor)
      throw error
    }
    self.descriptor = descriptor
    self.port = port
    self.acceptCall = acceptCall
    self.wakeRead = opened[0]
    self.wakeWrite = opened[1]
    self.placeholder = opened[2]
  }

  /// Ends the loop and frees the address; call once.
  func wake() {
    lock.withLock {
      closeWakeWrite()
      if descriptorOpen, dup2(placeholder, descriptor) < 0 {
        print(
          "[EndpointServer] Listener on port \(port) stays bound: dup2 failed with errno \(errno)"
        )
      }
      closePlaceholder()
    }
  }

  /// Closes a listener whose loop never started.
  func discard() {
    lock.withLock { closeWakeWrite() }
    finish()
  }

  /// Called by the loop when it ends.
  func finish() {
    lock.withLock {
      if descriptorOpen {
        Darwin.close(descriptor)
        descriptorOpen = false
        Darwin.close(wakeRead)
      }
      closePlaceholder()
    }
  }

  /// Blocks until a connection is waiting or the listener is woken.
  func wait() -> Wait {
    var polled = [
      pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0),
      pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0),
    ]
    while true {
      guard unsafe poll(&polled, nfds_t(polled.count), -1) >= 0 else {
        if errno == EINTR { continue }
        return .failed(errno)
      }
      if polled[0].revents != 0 { return .woken }
      let events = polled[1].revents
      if events & Int16(POLLIN) != 0 { return .ready }
      if events & Int16(POLLNVAL) != 0 { return .failed(EBADF) }
      if events != 0 { return .failed(EIO) }
    }
  }

  /// Accepts one connection as a blocking descriptor; nil when none was taken (`errno` says why).
  func accept() -> Int32? {
    let accepted = acceptCall(descriptor)
    guard accepted >= 0 else { return nil }
    // A connection accepted from a nonblocking listener is nonblocking too.
    let flags = fcntl(accepted, F_GETFL)
    guard flags >= 0, fcntl(accepted, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
      let code = errno
      Darwin.close(accepted)
      print(
        "[EndpointServer] Connection dropped: making it blocking failed with errno \(code)"
      )
      errno = ECONNABORTED
      return nil
    }
    return accepted
  }

  /// Call with `lock` held.
  private func closeWakeWrite() {
    guard wakeWriteOpen else { return }
    Darwin.close(wakeWrite)
    wakeWriteOpen = false
  }

  /// Call with `lock` held.
  private func closePlaceholder() {
    guard placeholder >= 0 else { return }
    Darwin.close(placeholder)
    placeholder = -1
  }
}
