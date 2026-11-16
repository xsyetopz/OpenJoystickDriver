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
  func stickYIsPositiveDownAndNotNegated() {
    let stick = StickPosition(x: 0.5, y: 0.25)
    #expect(stick.x == BipolarValue(normalized: 0.5))
    #expect(stick.y == BipolarValue(normalized: 0.25))
  }

  @Test
  func pushingStickUpReadsNegativeY() {
    let up = StickPosition(x: 0, y: -1)
    #expect(up.y == .min)
    #expect(up.y.rawValue < 0)
    let down = StickPosition(x: 0, y: 1)
    #expect(down.y.rawValue > 0)
  }

  @Test
  func encodingIsDeterministicAndRoundTrips() throws {
    var state = ControllerState.neutral
    state.pressed = [.start, .south, .guide]
    state.hat = .northWest
    state.leftStick = StickPosition(x: BipolarValue(1200), y: BipolarValue(-32767))
    state.rightTrigger = UnipolarValue(65535)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(state)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["pressed"] as? [String] == ["South", "Start", "Guide"])
    #expect(object["hat"] as? String == "NorthWest")
    #expect(try JSONDecoder().decode(ControllerState.self, from: data) == state)
  }

  @Test
  func recordTouchKeepsLatestFrameOfEachSurface() {
    var state = ControllerState.neutral
    state.recordTouch([touch(.left, 1), touch(.right, 2), touch(.left, 3)])
    #expect(state.touch.map(\.surface) == [.right, .left])
    #expect(state.touch.last?.timestamp == MonotonicTimestamp(nanoseconds: 3))
  }

  @Test
  func sleepGateTreatsSubThresholdSticksAndTriggersAsNeutral() {
    var state = ControllerState.neutral
    state.leftStick = StickPosition(x: 0.1, y: 0)
    state.leftTrigger = UnipolarValue(normalized: 0.04)
    #expect(state.isEffectivelyNeutral)
    state.rightTrigger = UnipolarValue(normalized: 0.3)
    #expect(!state.isEffectivelyNeutral)
    state.rightTrigger = .min
    state.pressed = [.south]
    #expect(!state.isEffectivelyNeutral)
  }

  /// Every release is delivered before any press, so a swap never holds both buttons; releases
  /// and presses each keep the control order.
  @Test
  func releasesComeBeforePresses() {
    let before = ControllerState(pressed: [.back, .east])
    let after = ControllerState(pressed: [.start, .south, .east])
    #expect(
      RemappingEngineState.changes(from: before, to: after) == [
        .button(.back, isPressed: false),
        .button(.south, isPressed: true), .button(.start, isPressed: true),
      ]
    )
    let swap = RemappingEngineState.changes(
      from: ControllerState(pressed: [.back]),
      to: ControllerState(pressed: [.start])
    )
    #expect(swap == [.button(.back, isPressed: false), .button(.start, isPressed: true)])
  }

  @Test
  func snapshotChangesFollowOneControlOrder() {
    var next = ControllerState.neutral
    next.pressed = [.north, .south, .start, .leftStickClick]
    next.hat = .east
    next.leftTrigger = UnipolarValue(1)
    next.rightStick = StickPosition(x: BipolarValue(10), y: BipolarValue(20))
    let changes = RemappingEngineState.changes(from: .neutral, to: next)
    #expect(
      changes == [
        .button(.south, isPressed: true), .button(.north, isPressed: true),
        .button(.leftStickClick, isPressed: true), .button(.start, isPressed: true),
        .dpad(.east),
        .rightStick(x: BipolarValue(10).normalized, y: BipolarValue(20).normalized),
        .leftTrigger(UnipolarValue(1).normalized),
      ]
    )
    #expect(RemappingEngineState.changes(from: next, to: next).isEmpty)

    // Back comes before the left trigger button, which comes before the first auxiliary.
    let joyCon = ControllerState(pressed: [.auxiliary3, .leftTrigger, .back])
    #expect(
      RemappingEngineState.changes(from: .neutral, to: joyCon) == [
        .button(.back, isPressed: true), .button(.leftTrigger, isPressed: true),
        .button(.auxiliary3, isPressed: true),
      ]
    )
    #expect(
      RemappingEngineState.changes(from: joyCon, to: .neutral) == [
        .button(.back, isPressed: false), .button(.leftTrigger, isPressed: false),
        .button(.auxiliary3, isPressed: false),
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
