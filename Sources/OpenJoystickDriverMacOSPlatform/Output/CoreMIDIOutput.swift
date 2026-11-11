import CoreMIDI
import Foundation
package import OpenJoystickDriverKit

/// Publishes the virtual CoreMIDI source `OpenJoystickDriver` and sends messages through it.
package final class CoreMIDIOutput: RemappingMIDIOutput, @unchecked Sendable {
  /// The client and source while the source is open.
  private struct Endpoint {
    /// The client that owns the source.
    let client: MIDIClientRef
    /// The virtual source.
    let source: MIDIEndpointRef
  }

  /// Name that a music app lists.
  private static let sourceName = "OpenJoystickDriver"

  /// The open endpoint, or `nil`.
  private let endpoint = Locked<Endpoint?>(nil)

  /// Creates an output with no source.
  package init() {}

  /// Creates the client and the virtual source, or keeps the open ones.
  /// - Throws: ``RemappingMIDIError/sourceRefused(status:)`` when CoreMIDI fails.
  package func open() throws {
    try endpoint.withLock { endpoint in
      guard endpoint == nil else { return }
      var client = MIDIClientRef()
      var status = unsafe MIDIClientCreate(Self.sourceName as CFString, nil, nil, &client)
      guard status == noErr else { throw RemappingMIDIError.sourceRefused(status: status) }
      var source = MIDIEndpointRef()
      status = unsafe MIDISourceCreateWithProtocol(
        client,
        Self.sourceName as CFString,
        ._1_0,
        &source
      )
      guard status == noErr else {
        MIDIClientDispose(client)
        throw RemappingMIDIError.sourceRefused(status: status)
      }
      endpoint = Endpoint(client: client, source: source)
    }
  }

  /// Sends a message as one MIDI 1.0 channel voice word.
  /// - Throws: ``RemappingMIDIError/sourceRefused(status:)`` when the source is not open or
  ///   CoreMIDI refuses the message.
  package func send(_ message: RemappingMIDIMessage) throws {
    let bytes = message.bytes
    let word =
      UInt32(0x2000_0000) | UInt32(bytes[0]) << 16 | UInt32(bytes[1]) << 8
      | UInt32(bytes[2])
    try endpoint.withLock { endpoint in
      guard let endpoint else { throw RemappingMIDIError.sourceRefused(status: kMIDIInvalidClient) }
      let builder = MIDIEventList.Builder(inProtocol: ._1_0, wordSize: 4)
      unsafe builder.append(timestamp: mach_absolute_time(), words: [word])
      let status = unsafe builder.withUnsafePointer {
        unsafe MIDIReceivedEventList(endpoint.source, $0)
      }
      guard status == noErr else { throw RemappingMIDIError.sourceRefused(status: status) }
    }
  }

  /// Removes the source and its client.
  package func close() {
    endpoint.withLock { endpoint in
      guard let open = endpoint else { return }
      MIDIEndpointDispose(open.source)
      MIDIClientDispose(open.client)
      endpoint = nil
    }
  }
}
