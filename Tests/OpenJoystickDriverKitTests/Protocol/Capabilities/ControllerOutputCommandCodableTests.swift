import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// The `sendControllerOutput` RPC JSON shape of commands and results.
struct ControllerOutputCommandCodableTests {
  func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try #require(String(bytes: try encoder.encode(value), encoding: .utf8))
  }

  @Test
  func commandsEncodeToTheDocumentedShape() throws {
    let rumble = RumbleIntensities(leftMain: .max, rightTrigger: UnipolarValue(257))
    let cases: [(ControllerOutputCommand, String)] = [
      (
        .setRumble(rumble, duration: .milliseconds(450)),
        #"{"duration":{"milliseconds":450},"intensities":{"leftHaptic":0,"leftMain":65535,"#
          + #""leftTrigger":0,"rightHaptic":0,"rightMain":0,"rightTrigger":257},"#
          + #""type":"set-rumble"}"#
      ),
      (
        .setRumble(.off, duration: .held),
        #"{"duration":"held","intensities":{"leftHaptic":0,"leftMain":0,"leftTrigger":0,"#
          + #""rightHaptic":0,"rightMain":0,"rightTrigger":0},"type":"set-rumble"}"#
      ), (.stopRumble, #"{"type":"stop-rumble"}"#),
      (.setPlayerIndicator(.player2), #"{"player":2,"type":"set-player-indicator"}"#),
      (
        .setRGB(ControllerColor(red: 17, green: 34, blue: 51)),
        #"{"blue":51,"green":34,"red":17,"type":"set-rgb"}"#
      ),
      (
        .setLightBrightness(UnipolarValue(byte: 0x80)),
        #"{"brightness":32896,"type":"set-light-brightness"}"#
      ),
      (
        .setAdaptiveTrigger(
          .left,
          PhysicalAdaptiveTriggerEffect(kind: .resistance, startPosition: 0.5, strength: 1)
        ),
        #"{"effect":{"kind":"resistance","startPosition":0.5,"strength":1},"trigger":"left","#
          + #""type":"set-adaptive-trigger"}"#
      ),
    ]
    for (command, expected) in cases {
      #expect(try json(command) == expected)
      let decoded = try JSONDecoder().decode(
        ControllerOutputCommand.self,
        from: Data(expected.utf8)
      )
      #expect(decoded == command)
    }
  }

  @Test
  func omittedRumbleChannelsDecodeAsOffAndUnknownFormsAreRejected() throws {
    let partial = #"{"type":"set-rumble","intensities":{"leftMain":65535},"duration":"held"}"#
    #expect(
      try JSONDecoder().decode(ControllerOutputCommand.self, from: Data(partial.utf8))
        == .setRumble(RumbleIntensities(leftMain: .max), duration: .held)
    )
    for invalid in [
      #"{"type":"set-rumble","intensities":{},"duration":"forever"}"#, #"{"type":"blink"}"#,
      #"{"type":"set-rgb","red":256,"green":0,"blue":0}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ControllerOutputCommand.self, from: Data(invalid.utf8))
      }
    }
  }

  /// A duration outside `0...5000` ms and an intensity key that names no motor, such as a typo,
  /// fail decoding instead of being clamped or read as off.
  @Test
  func outOfRangeDurationsAndUnknownMotorsAreRejected() throws {
    for milliseconds in [0, 5_000] {
      let body =
        #"{"type":"set-rumble","intensities":{},"#
        + #""duration":{"milliseconds":\#(milliseconds)}}"#
      #expect(
        try JSONDecoder().decode(ControllerOutputCommand.self, from: Data(body.utf8))
          == .setRumble(.off, duration: .milliseconds(milliseconds))
      )
    }
    for invalid in [
      #"{"type":"set-rumble","intensities":{},"duration":{"milliseconds":-1}}"#,
      #"{"type":"set-rumble","intensities":{},"duration":{"milliseconds":5001}}"#,
      #"{"type":"set-rumble","intensities":{"leftMian":65535},"duration":"held"}"#,
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(ControllerOutputCommand.self, from: Data(invalid.utf8))
      }
    }
  }

  /// A selector ID outside `UInt16` fails the request instead of matching no controller.
  @Test
  func requestArgumentsRejectOutOfRangeIDs() throws {
    let command = #""command":{"type":"stop-rumble"}"#
    let valid = #"{"vendorID":65535,"productID":0,"# + command + "}"
    let decoded = try JSONDecoder().decode(
      LocalServiceRPCControllerOutputArguments.self,
      from: Data(valid.utf8)
    )
    #expect(decoded.vendorID == 0xFFFF && decoded.command == .stopRumble)
    for invalid in [
      #"{"vendorID":65536,"productID":0,"# + command + "}",
      #"{"vendorID":1,"productID":-1,"# + command + "}",
    ] {
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
          LocalServiceRPCControllerOutputArguments.self,
          from: Data(invalid.utf8)
        )
      }
    }
  }

  @Test
  func resultsEncodeTheOutcomeAndDroppedChannels() throws {
    #expect(
      try json(ControllerOutputResult(.delivered, droppedRumbleChannels: [.leftTrigger]))
        == #"{"droppedRumbleChannels":["leftTrigger"],"outcome":"delivered"}"#
    )
    #expect(
      ControllerOutputResult.Outcome.allCases.map(\.rawValue) == [
        "delivered", "notFound", "unsupportedCapability", "notReady", "invalidValue",
        "writeFailed", "cancelled",
      ]
    )
  }
}
