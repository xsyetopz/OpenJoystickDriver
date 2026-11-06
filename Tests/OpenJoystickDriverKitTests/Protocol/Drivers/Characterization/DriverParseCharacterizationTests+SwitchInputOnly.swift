import Foundation
import Testing

@testable import OpenJoystickDriverKit

// Pinned parse transcript; the rendering rules are on `DriverParseCharacterizationTests`.
extension DriverParseCharacterizationTests {
  /// The 7-byte SDL `SwitchInputOnlyControllerStatePacket_t` report of a wired Switch pad: two
  /// button bytes, a hat byte (0 north clockwise to 7, 8 neutral), then four stick bytes centered
  /// on 128 with up and left low.
  ///
  /// The resting report is the one `SwitchInputOnlyParserTests` feeds the driver.
  @Test
  func switchInputOnly() throws {
    let lines = try transcript(
      DriverLifecycleCharacterizationTests.switchInputOnly,
      Self.switchInputOnlySteps
    )
    #expect(lines == Self.switchInputOnlyTranscript)
  }

  static let switchInputOnlyTranscript: [String] = [
    "neutral [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.0 [West] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.1 [South] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.2 [East] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.3 [North] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.4 [LeftShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.5 [RightShoulder] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.6 [LeftTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b0.7 [RightTrigger] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.0 [Back] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.1 [Start] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.2 [LeftStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.3 [RightStickClick] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.4 [Guide] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "b1.5 [Capture] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "h0 [] hat=North ls=0,0 rs=0,0 lt=0 rt=0",
    "h1 [] hat=NorthEast ls=0,0 rs=0,0 lt=0 rt=0",
    "h2 [] hat=East ls=0,0 rs=0,0 lt=0 rt=0",
    "h3 [] hat=SouthEast ls=0,0 rs=0,0 lt=0 rt=0",
    "h4 [] hat=South ls=0,0 rs=0,0 lt=0 rt=0",
    "h5 [] hat=SouthWest ls=0,0 rs=0,0 lt=0 rt=0",
    "h6 [] hat=West ls=0,0 rs=0,0 lt=0 rt=0",
    "h7 [] hat=NorthWest ls=0,0 rs=0,0 lt=0 rt=0",
    "h8 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "h9 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "hff [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "s3=0 [] hat=Neutral ls=-32767,0 rs=0,0 lt=0 rt=0",
    "s3=1 [] hat=Neutral ls=-32511,0 rs=0,0 lt=0 rt=0",
    "s3=7f [] hat=Neutral ls=-255,0 rs=0,0 lt=0 rt=0",
    "s3=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "s3=81 [] hat=Neutral ls=258,0 rs=0,0 lt=0 rt=0",
    "s3=ff [] hat=Neutral ls=32767,0 rs=0,0 lt=0 rt=0",
    "s4=0 [] hat=Neutral ls=0,-32767 rs=0,0 lt=0 rt=0",
    "s4=1 [] hat=Neutral ls=0,-32511 rs=0,0 lt=0 rt=0",
    "s4=7f [] hat=Neutral ls=0,-255 rs=0,0 lt=0 rt=0",
    "s4=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "s4=81 [] hat=Neutral ls=0,258 rs=0,0 lt=0 rt=0",
    "s4=ff [] hat=Neutral ls=0,32767 rs=0,0 lt=0 rt=0",
    "s5=0 [] hat=Neutral ls=0,0 rs=-32767,0 lt=0 rt=0",
    "s5=1 [] hat=Neutral ls=0,0 rs=-32511,0 lt=0 rt=0",
    "s5=7f [] hat=Neutral ls=0,0 rs=-255,0 lt=0 rt=0",
    "s5=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "s5=81 [] hat=Neutral ls=0,0 rs=258,0 lt=0 rt=0",
    "s5=ff [] hat=Neutral ls=0,0 rs=32767,0 lt=0 rt=0",
    "s6=0 [] hat=Neutral ls=0,0 rs=0,-32767 lt=0 rt=0",
    "s6=1 [] hat=Neutral ls=0,0 rs=0,-32511 lt=0 rt=0",
    "s6=7f [] hat=Neutral ls=0,0 rs=0,-255 lt=0 rt=0",
    "s6=80 [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "s6=81 [] hat=Neutral ls=0,0 rs=0,258 lt=0 rt=0",
    "s6=ff [] hat=Neutral ls=0,0 rs=0,32767 lt=0 rt=0",
    "repeat [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
    "short [] hat=Neutral ls=0,0 rs=0,0 lt=0 rt=0",
  ]

  static var switchInputOnlySteps: [Step] {
    let base: [UInt8] = [0, 0, 0x08, 0x80, 0x80, 0x80, 0x80]
    return [Step("neutral", base)]
      + bitSteps(base, [(0, 0xFF), (1, 0x3F)])
      + valueSteps(base, offset: 2, prefix: "h", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xFF])
      + (3...6).flatMap {
        valueSteps(base, offset: $0, prefix: "s\($0)=", [0, 1, 0x7F, 0x80, 0x81, 0xFF])
      } + [Step("repeat", base), Step("short", Array(base.prefix(6)))]
  }
}
