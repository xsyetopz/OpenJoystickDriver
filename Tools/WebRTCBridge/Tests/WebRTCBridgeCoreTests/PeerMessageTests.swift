import XCTest

@testable import BridgeCore
@testable import WebRTCBridgeCore

/// Checks ``PeerMessage`` and ``FrameMailbox`` against the schemas and invalid input.
final class PeerMessageTests: XCTestCase {
  /// The `apiVersion` member of every message, as JSON text.
  private static let header = #""apiVersion":"openjoystickdriver/v1alpha2""#

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
    let schema = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
    let entry = try XCTUnwrap(definitions[definition] as? [String: Any])
    return Set(try XCTUnwrap(entry["enum"] as? [String]))
  }

  /// The frame lists of ``PeerMessage`` equal the enumerations of the schemas.
  func testTheFrameListsMatchTheSchemas() throws {
    let control = try schemaEnum("vocabulary.schema.json", "control")
    let withoutButtons = try schemaEnum("vocabulary.schema.json", "dpadControl")
      .union(schemaEnum("vocabulary.schema.json", "stickAxis"))
    XCTAssertEqual(PeerMessage.buttons, control.subtracting(withoutButtons))
    XCTAssertEqual(PeerMessage.axes, try schemaEnum("vocabulary.schema.json", "gamepadAxis"))
    XCTAssertEqual(PeerMessage.dpad, try schemaEnum("vocabulary.schema.json", "dpadControl"))
  }

  /// A valid frame is rebuilt from the checked fields.
  func testAValidFrameIsRebuiltFromTheCheckedFields() throws {
    let line = try XCTUnwrap(
      PeerMessage.frame(
        from: frame(
          #","buttons":["South"],"dpad":["DpadUp"],"axes":{"LeftStickX":0.5}"#
            + #","holdMilliseconds":60000"#
        )
      )
    )
    XCTAssertEqual(line["buttons"] as? [String], ["South"])
    XCTAssertEqual(line["holdMilliseconds"] as? Int, 60000)
    XCTAssertEqual((line["axes"] as? [String: Double])?["LeftStickX"], 0.5)
  }

  /// A frame longer than `maximumBytes` is rejected.
  func testAFrameThatIsTooLongIsRejected() {
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    XCTAssertNil(PeerMessage.frame(from: Data((frame().utf8String + padding).utf8)))
  }

  /// Frames with the wrong shape, values or members are rejected.
  func testAFrameThatIsNotShapedLikeAFrameIsRejected() {
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
      XCTAssertNil(PeerMessage.frame(from: data), data.utf8String)
    }
  }

  /// The `intensities` member with all six intensities, as JSON text.
  private static let allIntensities =
    #""intensities":{"lowFrequency":65535,"highFrequency":0,"leftTrigger":1,"rightTrigger":2,"#
    + #""leftHaptic":3,"rightHaptic":4}"#

  /// Valid `SetRumble` and `StopRumble` commands are accepted.
  func testAValidRumbleCommandIsAccepted() throws {
    let line = try XCTUnwrap(
      PeerMessage.rumble(
        from: rumble(#","type":"SetRumble",\#(Self.allIntensities),"durationMilliseconds":5000"#)
      )
    )
    XCTAssertEqual(line["type"] as? String, "SetRumble")
    XCTAssertEqual((line["intensities"] as? [String: Int])?["lowFrequency"], 65535)
    XCTAssertEqual(line["durationMilliseconds"] as? Int, 5000)
    XCTAssertNotNil(
      PeerMessage.rumble(from: rumble(#","type":"SetRumble",\#(Self.allIntensities)"#))
    )
    XCTAssertNotNil(PeerMessage.rumble(from: rumble(#","type":"StopRumble""#)))
  }

  /// Rumble commands with the wrong shape, values or length are rejected.
  func testARumbleCommandThatIsNotShapedLikeOneIsRejected() {
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
      XCTAssertNil(PeerMessage.rumble(from: data), data.utf8String)
    }
    let outOfRange = [
      all.replacingOccurrences(of: "65535", with: "65536"),
      all.replacingOccurrences(of: "\"highFrequency\":0", with: "\"highFrequency\":-1"),
      all.replacingOccurrences(of: "\"highFrequency\":0", with: "\"highFrequency\":0.5"),
    ]
    for intensities in outOfRange {
      XCTAssertNil(PeerMessage.rumble(from: rumble(#","type":"SetRumble",\#(intensities)"#)))
    }
    let padding = String(repeating: " ", count: PeerMessage.maximumBytes)
    XCTAssertNil(
      PeerMessage.rumble(from: Data((rumble(#","type":"StopRumble""#).utf8String + padding).utf8))
    )
  }

  /// A mailbox returns only the newest frame, and then nothing.
  func testTheMailboxKeepsOnlyTheNewestFrame() {
    let mailbox = FrameMailbox()
    for index in 1...3 { mailbox.post(["n": index]) }
    XCTAssertEqual(mailbox.next(timeout: 1)?["n"] as? Int, 3)
    XCTAssertNil(mailbox.next(timeout: 0.05))
  }

  /// A post that races the timeout is returned once and leaves nothing behind.
  func testAPostThatRacesTheTimeoutIsNeitherLostNorRepeated() {
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
      XCTAssertNil(mailbox.next(timeout: 0.01))
      XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.009)
    }
    XCTAssertEqual(received, 300)
  }

  /// A blob longer than `maximumBytes` is refused, with the limit in the error.
  func testABlobThatIsTooLongIsRefused() {
    let blob = String(repeating: "A", count: PeerMessage.maximumBytes + 1)
    XCTAssertThrowsError(try PeerLink.decode(blob)) { error in
      XCTAssertTrue("\(error)".contains("65536"), "\(error)")
    }
  }
}

extension Data {
  /// The data as UTF-8 text, or an empty string when it is not UTF-8.
  var utf8String: String { String(bytes: self, encoding: .utf8) ?? "" }
}
