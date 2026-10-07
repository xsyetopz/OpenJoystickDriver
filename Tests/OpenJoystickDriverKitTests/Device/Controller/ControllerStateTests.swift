import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct ControllerStateTests {
  @Test
  func normalizedValuesTruncateTowardZeroAndClamp() {
    #expect(BipolarValue(normalized: 0.151).rawValue == 4947)
    #expect(BipolarValue(normalized: -0.1).rawValue == -3276)
    #expect(BipolarValue(normalized: 1.5).rawValue == 32767)
    #expect(BipolarValue(normalized: -1.0000305).rawValue == -32767)
    #expect(BipolarValue(-32768).rawValue == -32767)
    #expect(BipolarValue(normalized: .nan) == .center)
    #expect(UnipolarValue(normalized: 511.0 / 1023.0).rawValue == 32735)
    #expect(UnipolarValue(normalized: 1024.0 / 1023.0) == .max)
    #expect(UnipolarValue(normalized: -0.5) == .min)
    #expect(UnipolarValue(normalized: .infinity) == .min)
  }

  @Test
  func stickYDownIsNegatedOnceIntoTheCanonicalFrame() {
    let stick = StickPosition(x: 0.5, yDown: 0.25)
    #expect(stick.x == BipolarValue(normalized: 0.5))
    #expect(stick.y == BipolarValue(normalized: -0.25))
  }

  @Test
  func encodingIsDeterministicAndRoundTrips() throws {
    var state = ControllerState.neutral
    state.pressed = [.menu, .faceSouth, .guide]
    state.hat = .northWest
    state.leftStick = StickPosition(x: BipolarValue(1200), y: BipolarValue(-32767))
    state.rightTrigger = UnipolarValue(65535)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(state)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["pressed"] as? [String] == ["face-south", "menu", "guide"])
    #expect(object["hat"] as? String == "northWest")
    #expect(try JSONDecoder().decode(ControllerState.self, from: data) == state)
  }

  @Test
  func recordTouchKeepsTheLatestFrameOfEachSurface() {
    var state = ControllerState.neutral
    state.recordTouch([touch(.left, 1), touch(.right, 2), touch(.left, 3)])
    #expect(state.touch.map(\.surface) == [.right, .left])
    #expect(state.touch.last?.timestamp == MonotonicTimestamp(nanoseconds: 3))
  }

  @Test
  func sleepGateTreatsSubThresholdSticksAndTriggersAsNeutral() {
    var state = ControllerState.neutral
    state.leftStick = StickPosition(x: 0.1, yDown: 0)
    state.leftTrigger = UnipolarValue(normalized: 0.04)
    #expect(state.isEffectivelyNeutral)
    state.rightTrigger = UnipolarValue(normalized: 0.3)
    #expect(!state.isEffectivelyNeutral)
    state.rightTrigger = .min
    state.pressed = [.faceSouth]
    #expect(!state.isEffectivelyNeutral)
  }

  @Test
  func snapshotChangesFollowTheDeltaPipelineOrder() {
    var next = ControllerState.neutral
    next.pressed = [.faceNorth, .faceSouth, .menu, .leftStickClick]
    next.hat = .east
    next.leftTrigger = UnipolarValue(1)
    next.rightStick = StickPosition(x: BipolarValue(10), y: BipolarValue(20))
    let standard = RemappingEngineState.changes(from: .neutral, to: next, labels: .standard)
    #expect(
      standard == [
        .button(.south, isPressed: true), .button(.north, isPressed: true),
        .button(.leftStick, isPressed: true), .button(.start, isPressed: true), .dpad(.east),
        .rightStick(x: BipolarValue(10).normalized, y: -BipolarValue(20).normalized),
        .leftTrigger(UnipolarValue(1).normalized),
      ]
    )
    let playStation = RemappingEngineState.changes(from: .neutral, to: next, labels: .playStation)
    #expect(
      playStation.prefix(4) == [
        .button(.leftStick, isPressed: true), .button(.south, isPressed: true),
        .button(.north, isPressed: true), .button(.options, isPressed: true),
      ]
    )
    #expect(RemappingEngineState.changes(from: next, to: next, labels: .standard).isEmpty)

    // Former Button order: back before l2Digital before leftSL, for presses and releases alike.
    let joyCon = ControllerState(pressed: [.auxiliary3, .leftTriggerButton, .view])
    #expect(
      RemappingEngineState.changes(from: .neutral, to: joyCon, labels: .nintendo) == [
        .button(.back, isPressed: true), .button(.leftTriggerClick, isPressed: true),
        .button(.leftSL, isPressed: true),
      ]
    )
    #expect(
      RemappingEngineState.changes(from: joyCon, to: .neutral, labels: .nintendo) == [
        .button(.back, isPressed: false), .button(.leftTriggerClick, isPressed: false),
        .button(.leftSL, isPressed: false),
      ]
    )
  }

  private func touch(_ surface: ControllerTouchSurface, _ time: UInt64) -> ControllerTouchSample {
    ControllerTouchSample(
      surface: surface,
      timestamp: MonotonicTimestamp(nanoseconds: time),
      contacts: []
    )
  }
}
