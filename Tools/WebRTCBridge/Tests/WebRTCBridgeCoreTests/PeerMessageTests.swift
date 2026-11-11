import Foundation
import Testing

@testable import BridgeCore
@testable import WebRTCBridgeCore

/// Checks ``PeerMessage`` and ``FrameMailbox`` against the schemas and invalid input.
final class PeerMessageTests {
  /// The `apiVersion` member of every message, as JSON text.
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha3""#

  /// A `Frame` message with the given extra members, as data.
  private func frame(_ members: String = "") -> Data {
    Data(#"{\#(Self.header),"kind":"Frame"\#(members)}"#.utf8)
  }

  /// A `RumbleCommand` message with the given extra members, as data.
  private func rumble(_ members: String = #","type":"SetRumble""#) -> Data {
    Data(#"{\#(Self.header),"kind":"RumbleCommand"\#(members)}"#.utf8)
  }

  /// The `enum` values of a `$defs` entry of a file in `Resources/Schemas`.
  private func schemaEnum(_ file: String, _ definition: String) throws -> Set<String> {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("Resources/Schemas/\(file)"))
    let schema = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let entry = try #require(definitions[definition] as? [String: Any])
    return Set(try #require(entry["enum"] as? [String]))
  }

  /// The frame lists of ``PeerMessage`` equal the enumerations of the schemas.
  @Test
  func theFrameListsMatchTheSchemas() throws {
    let control = try schemaEnum("vocabulary.schema.json", "control")
    let withoutButtons = try schemaEnum("vocabulary.schema.json", "dpadControl")
      .union(schemaEnum("vocabulary.schema.json", "stickAxis"))
    #expect(PeerMessage.buttons == control.subtracting(withoutButtons))
    #expect(try PeerMessage.axes == schemaEnum("vocabulary.schema.json", "gamepadAxis"))
    #expect(try PeerMessage.dpad == schemaEnum("vocabulary.schema.json", "dpadControl"))
  }

  /// A valid frame is rebuilt from the checked fields.
  @Test
  func aValidFrameIsRebuiltFromTheCheckedFields() throws {
    let line = try #require(
      PeerMessage.frame(
        from: frame(
          #","buttons":["South"],"dpad":["DpadUp"],"axes":{"LeftStickX":0.5}"#
            + #","holdMilliseconds":60000"#
        )
      )
    )
    #expect((line["buttons"] as? [String]) == ["South"])
    #expect((line["holdMilliseconds"] as? Int) == 60000)
    #expect((line["axes"] as? [String: Double])?["LeftStickX"] == 0.5)
  }

  /// A frame longer than `maximumBytes` is rejected.
  @Test
  func aFrameThatIsTooLongIsRejected() {
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    #expect(PeerMessage.frame(from: Data((frame().utf8String + padding).utf8)) == nil)
  }

  /// Frames with the wrong shape, values or members are rejected.
  @Test
  func aFrameThatIsNotShapedLikeAFrameIsRejected() {
    let rejected = [
      Data("not json".utf8),
      Data("[]".utf8),
      Data(#"{"apiVersion":"other","kind":"Frame"}"#.utf8),
      Data(#"{\#(Self.header),"kind":"Hello"}"#.utf8),
      Data(#"{"kind":"Frame"}"#.utf8),
      frame(#","extra":1"#),
      frame(#","holdMilliseconds":60001"#),
      frame(#","holdMilliseconds":-1"#),
      frame(#","holdMilliseconds":1.5"#),
      frame(#","holdMilliseconds":true"#),
      frame(#","buttons":["nope"]"#), frame(#","buttons":["south"]"#),
      frame(#","axes":{"notAName":0.5}"#),
      frame(#","buttons":["South","South"]"#),
      frame(#","buttons":"South""#),
      frame(#","dpad":["diagonal"]"#),
      frame(#","axes":{"nope":0.5}"#),
      frame(#","axes":{"LeftStickX":true}"#),
      frame(#","axes":{"LeftStickX":"0.5"}"#),
      frame(#","axes":{"LeftStickX":1e999}"#),
    ]
    for data in rejected {
      #expect(PeerMessage.frame(from: data) == nil, Comment(rawValue: data.utf8String))
    }
  }

  /// The `intensities` member with all six intensities, as JSON text.
  private static let allIntensities =
    #""intensities":{"lowFrequency":65535,"highFrequency":0,"leftTrigger":1,"rightTrigger":2,"#
    + #""leftHaptic":3,"rightHaptic":4}"#

  /// Valid `SetRumble` and `StopRumble` commands are accepted.
  @Test
  func aValidRumbleCommandIsAccepted() throws {
    let line = try #require(
      PeerMessage.rumble(
        from: rumble(#","type":"SetRumble",\#(Self.allIntensities),"durationMilliseconds":5000"#)
      )
    )
    #expect((line["type"] as? String) == "SetRumble")
    #expect((line["intensities"] as? [String: Int])?["lowFrequency"] == 65535)
    #expect((line["durationMilliseconds"] as? Int) == 5000)
    #expect(
      PeerMessage.rumble(from: rumble(#","type":"SetRumble",\#(Self.allIntensities)"#)) != nil
    )
    #expect(PeerMessage.rumble(from: rumble(#","type":"StopRumble""#)) != nil)
  }

  /// Rumble commands with the wrong shape, values or length are rejected.
  @Test
  func aRumbleCommandThatIsNotShapedLikeOneIsRejected() {
    let all = Self.allIntensities
    let rejected = [
      Data("not json".utf8),
      Data(#"{\#(Self.header),"kind":"Frame"}"#.utf8),
      Data(#"{"apiVersion":"other","kind":"RumbleCommand","type":"StopRumble"}"#.utf8),
      rumble(""),
      rumble(#","type":"explode""#),
      rumble(#","type":"SetRumble",\#(all),"extra":1"#),
      rumble(#","type":"SetRumble",\#(all),"durationMilliseconds":5001"#),
      rumble(#","type":"SetRumble",\#(all),"durationMilliseconds":-5"#),
      rumble(#","type":"SetRumble""#),
      rumble(#","type":"SetRumble","intensities":{"lowFrequency":1}"#),
      rumble(#","type":"SetRumble","intensities":{"middle":1}"#),
      rumble(#","type":"StopRumble","durationMilliseconds":0"#),
      rumble(#","type":"StopRumble","intensities":{}"#),
      rumble(#","type":"StopRumble","extra":1"#),
      rumble(#","type":"setRumble",\#(all)"#),
      rumble(#","type":"stopRumble""#),
    ]
    for data in rejected {
      #expect(PeerMessage.rumble(from: data) == nil, Comment(rawValue: data.utf8String))
    }
    let outOfRange = [
      all.replacingOccurrences(of: "65535", with: "65536"),
      all.replacingOccurrences(of: "\"highFrequency\":0", with: "\"highFrequency\":-1"),
      all.replacingOccurrences(of: "\"highFrequency\":0", with: "\"highFrequency\":0.5"),
    ]
    for intensities in outOfRange {
      #expect(PeerMessage.rumble(from: rumble(#","type":"SetRumble",\#(intensities)"#)) == nil)
    }
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    #expect(
      PeerMessage.rumble(from: Data((rumble(#","type":"StopRumble""#).utf8String + padding).utf8))
        == nil
    )
  }

  /// A mailbox returns only the newest frame, and then nothing.
  @Test
  func theMailboxKeepsOnlyTheNewestFrame() {
    let mailbox = FrameMailbox()
    for index in 1...3 { mailbox.post(["n": index]) }
    #expect((mailbox.next(timeout: 1)?["n"] as? Int) == 3)
    #expect(mailbox.next(timeout: 0.05) == nil)
  }

  /// A post that races the timeout is returned once and leaves nothing behind.
  @Test
  func aPostThatRacesTheTimeoutIsNeitherLostNorRepeated() {
    let mailbox = FrameMailbox()
    var received = 0
    for index in 0..<300 {
      Thread.detachNewThread {
        Thread.sleep(forTimeInterval: 0.0005)
        mailbox.post(["n": index])
      }
      var got = false
      while !got { got = mailbox.next(timeout: 0.0005) != nil }
      received += 1
      // Nothing is left over: the next wait lasts for its whole timeout.
      let start = Date()
      #expect(mailbox.next(timeout: 0.01) == nil)
      #expect(Date().timeIntervalSince(start) >= 0.009)
    }
    #expect(received == 300)
  }

  /// A blob longer than `maximumBytes` is refused, with the limit in the error.
  @Test
  func aBlobThatIsTooLongIsRefused() {
    let blob = String(repeating: "A", count: PeerMessage.maximumBytes + 1)
    let error = #expect(throws: BridgeError.self) { try PeerLink.decode(blob) }
    #expect(error.map { "\($0)".contains("65536") } == true, "\(String(describing: error))")
  }
}

extension Data {
  /// The data as UTF-8 text, or an empty string when it is not UTF-8.
  var utf8String: String { String(bytes: self, encoding: .utf8) ?? "" }
}
