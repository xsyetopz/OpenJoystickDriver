import Darwin
import Foundation

/// RFC 6455 frames on an upgraded TCP connection: each text message is one endpoint line.
///
/// The reader answers ping with pong and echoes close itself; writes from both threads hold
/// `writeLock`, so frames never interleave.
///
/// - Note: `@unchecked Sendable` because `buffer` is touched only by the reading thread and
///   `closeSent` only under `writeLock`.
final class EndpointWebSocketTransport: EndpointTransport, @unchecked Sendable {
  /// The opcodes of the frames that the transport handles.
  private enum Opcode {
    /// A continuation of a text message.
    static let continuation: UInt8 = 0x0
    /// A text message.
    static let text: UInt8 = 0x1
    /// A binary message.
    static let binary: UInt8 = 0x2
    /// A close frame.
    static let close: UInt8 = 0x8
    /// A ping frame.
    static let ping: UInt8 = 0x9
    /// A pong frame.
    static let pong: UInt8 = 0xA
  }

  /// The result of reading one frame.
  private enum Frame {
    /// A frame with its final flag, opcode and unmasked payload.
    case frame(final: Bool, opcode: UInt8, payload: Data)
    /// The peer closed the stream.
    case end
    /// The frame is longer than the limit.
    case tooLong
    /// The frame is not accepted, with the reason.
    case invalid(String)
  }

  /// The connected socket.
  private let descriptor: Int32
  /// The lock that serializes writes.
  private let writeLock = NSLock()
  /// Whether the close frame was sent.
  private var closeSent = false
  /// The bytes read and not yet used.
  private var buffer: Data

  /// `buffered` holds bytes that arrived after the upgrade request.
  init(descriptor: Int32, buffered: Data) {
    self.descriptor = descriptor
    buffer = buffered
  }

  /// Reads frames until a whole text message arrives, and answers ping and close frames itself.
  func readMessage() -> EndpointReadResult {
    var message: Data?
    while true {
      switch readFrame() {
      case .end: return .end
      case .tooLong: return .tooLong
      case .invalid(let reason): return .invalid(reason)
      case .frame(let final, let opcode, let payload):
        switch opcode {
        case Opcode.close:
          writeLock.withLock {
            guard !closeSent else { return }
            closeSent = true
            _ = endpointSendAll(descriptor, Self.frame(Opcode.close, payload.prefix(2)))
          }
          return .end
        case Opcode.ping:
          writeLock.withLock {
            guard !closeSent else { return }
            _ = endpointSendAll(descriptor, Self.frame(Opcode.pong, payload))
          }
        case Opcode.pong: continue
        case Opcode.text, Opcode.continuation:
          guard (opcode == Opcode.text) == (message == nil) else {
            return .invalid("A continuation frame must follow an unfinished text frame.")
          }
          var joined = message ?? Data()
          joined.append(payload)
          guard joined.count <= EndpointServer.maximumLineBytes else { return .tooLong }
          if final { return .message(joined) }
          message = joined
        case Opcode.binary: return .invalid("Binary frames are not accepted; send text.")
        default: return .invalid("The frame has an unknown opcode.")
        }
      }
    }
  }

  /// Writes `data` as one text frame; false when a close was sent or the peer is gone.
  func writeMessage(_ data: Data) -> Bool {
    writeLock.withLock {
      !closeSent && endpointSendAll(descriptor, Self.frame(Opcode.text, data))
    }
  }

  /// Sends close with status 1000.
  func writeClose() {
    writeLock.withLock {
      guard !closeSent else { return }
      closeSent = true
      _ = endpointSendAll(descriptor, Self.frame(Opcode.close, Data([0x03, 0xE8])))
    }
  }

  // MARK: - Private

  /// Reads one client frame and unmasks its payload.
  private func readFrame() -> Frame {
    guard fill(2) else { return .end }
    let first = buffer[buffer.startIndex]
    let second = buffer[buffer.startIndex + 1]
    guard first & 0x70 == 0 else { return .invalid("The frame sets reserved bits.") }
    guard second & 0x80 != 0 else { return .invalid("Client frames must be masked.") }
    let opcode = first & 0x0F
    var length = Int(second & 0x7F)
    var headerLength = 2
    if length == 126 {
      guard fill(4) else { return .end }
      length = buffer.dropFirst(2).prefix(2).reduce(0) { $0 << 8 | Int($1) }
      headerLength = 4
    } else if length == 127 {
      guard fill(10) else { return .end }
      let bytes = buffer.dropFirst(2).prefix(8)
      guard bytes.prefix(4).allSatisfy({ $0 == 0 }) else { return .tooLong }
      length = bytes.reduce(0) { $0 << 8 | Int($1) }
      headerLength = 10
    }
    if opcode & 0x8 != 0, length > 125 || first & 0x80 == 0 {
      return .invalid("A control frame must be final and at most 125 bytes.")
    }
    guard length <= EndpointServer.maximumLineBytes else { return .tooLong }
    guard fill(headerLength + 4 + length) else { return .end }
    let start = buffer.startIndex + headerLength
    let mask = Array(buffer[start..<(start + 4)])
    var payload = Data(buffer[(start + 4)..<(start + 4 + length)])
    for index in payload.indices { payload[index] ^= mask[(index - payload.startIndex) % 4] }
    buffer.removeSubrange(buffer.startIndex..<(start + 4 + length))
    return .frame(final: first & 0x80 != 0, opcode: opcode, payload: payload)
  }

  /// Reads until `buffer` holds `count` bytes; false when the peer closed or the timeout passed.
  private func fill(_ count: Int) -> Bool {
    var chunk = [UInt8](repeating: 0, count: 16_384)
    while buffer.count < count {
      let received = unsafe Darwin.recv(descriptor, &chunk, chunk.count, 0)
      if received < 0, errno == EINTR { continue }
      guard received > 0 else { return false }
      buffer.append(contentsOf: chunk[0..<received])
    }
    return true
  }

  /// An unmasked server frame.
  private static func frame(_ opcode: UInt8, _ payload: Data) -> Data {
    var frame = Data([0x80 | opcode])
    switch payload.count {
    case 0..<126: frame.append(UInt8(payload.count))
    case 126..<65_536:
      frame.append(126)
      unsafe frame.append(
        contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian, Array.init)
      )
    default:
      frame.append(127)
      unsafe frame.append(
        contentsOf: withUnsafeBytes(of: UInt64(payload.count).bigEndian, Array.init)
      )
    }
    return frame + payload
  }
}
