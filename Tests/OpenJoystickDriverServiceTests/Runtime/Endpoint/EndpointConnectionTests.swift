import Darwin
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

/// The socket buffers hold a few dozen `connected` lines, so a client that does not read blocks
/// the writer and later lines wait in the connection's queue.
struct EndpointConnectionTests {
  @Test
  func waitingInputLinesOfAControllerAreReplacedByTheLatest() throws {
    let (connection, reader) = try Self.pair()
    connection.subscribe(output: false, snapshot: [])
    for index in 0..<100 { connection.deliver(Self.connected("pad-\(index)")) }
    for index in 0..<50 {
      let control: ControlID = index.isMultiple(of: 2) ? .faceSouth : .faceEast
      connection.deliver(
        ControllerWatchEvent(type: .input, id: "pad-0", input: ControllerState(pressed: [control]))
      )
    }
    connection.finish()

    let objects = Self.readAll(reader)
    let inputs = objects.filter { $0["type"] as? String == "input" }
    #expect(objects.count == 101)
    #expect(inputs.count == 1)
    #expect((inputs.first?["input"] as? [String: Any])?["pressed"] as? [String] == ["face-east"])
  }

  @Test
  func aClientThatFallsTooFarBehindIsClosedWithTooSlow() throws {
    let (connection, reader) = try Self.pair()
    connection.subscribe(output: false, snapshot: [])
    for index in 0..<1_000 { connection.deliver(Self.connected("pad-\(index)")) }

    let objects = Self.readAll(reader)
    #expect(objects.count < 1_000)
    #expect(objects.last?["code"] as? String == "E1007")
    connection.finish()
  }

  @Test
  func closingDropsTheRumbleLinesThatWait() throws {
    let (connection, reader) = try Self.pair()
    // Small buffers, so the writer blocks after a few rumble lines.
    var size: Int32 = 2_048
    let length = socklen_t(MemoryLayout<Int32>.size)
    setsockopt(connection.descriptor, SOL_SOCKET, SO_SNDBUF, &size, length)
    setsockopt(reader, SOL_SOCKET, SO_RCVBUF, &size, length)
    let count = EndpointServer.maximumQueuedLines - 1
    for index in 0..<count {
      let line = ControllerOutputCommand.setRumble(.off, duration: .milliseconds(index))
      connection.send(line, bounded: true)
    }
    connection.close(EndpointError(code: .revoked, message: "Revoked."))

    let objects = Self.readAll(reader)
    #expect(objects.count < count)
    #expect(objects.last?["code"] as? String == "E1006")
    connection.finish()
  }

  private static func connected(_ id: String) -> ControllerWatchEvent {
    ControllerWatchEvent(
      type: .connected,
      id: id,
      controller: ControllerSummary(.fixture(id: id))
    )
  }

  private static func pair() throws -> (EndpointConnection, Int32) {
    var descriptors: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    try LocalServiceRPCTransport.setTimeout(descriptors[1], seconds: 5)
    return (EndpointConnection(descriptor: descriptors[0]), descriptors[1])
  }

  /// Reads lines until the connection closes, then closes `descriptor`.
  private static func readAll(_ descriptor: Int32) -> [[String: Any]] {
    defer { close(descriptor) }
    var data = Data()
    var chunk = [UInt8](repeating: 0, count: 65_536)
    while true {
      let count = recv(descriptor, &chunk, chunk.count, 0)
      guard count > 0 else { break }
      data.append(contentsOf: chunk[0..<count])
    }
    return data.split(separator: UInt8(ascii: "\n")).compactMap {
      try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]
    }
  }
}
