import Testing
@testable import OpenJoystickDriverKit

struct FlickStickTests {
  @Test func outwardFlickRotatesAndRearmsOnlyAfterReturningInside() {
    var stick = RemappingFlickStick()
    let first = stick.process(x: 1, y: 0)
    #expect(first == .flick(degrees: 90))
    let stationary = stick.process(x: 0.85, y: 0)
    #expect(stationary == nil)
    let turn = stick.process(x: 0, y: 1)
    #expect(turn == .rotation(degrees: -90))
    let inward = stick.process(x: 0.7, y: 0)
    #expect(inward == nil)
    let rearmed = stick.process(x: -1, y: 0)
    #expect(rearmed == .flick(degrees: -90))
  }

  @Test func rimRotationCrossesRearSeamWithoutFullTurn() {
    var stick = RemappingFlickStick()
    _ = stick.process(x: 0.01, y: -1)
    let event = stick.process(x: -0.01, y: -1)
    guard case .rotation(let degrees) = event else {
      Issue.record("Expected a seam-crossing rotation")
      return
    }
    #expect(degrees > 0 && degrees < 2)
  }

  @Test func invalidInputDropsOldAngle() {
    var stick = RemappingFlickStick()
    _ = stick.process(x: 1, y: 0)
    let invalid = stick.process(x: .nan, y: 0)
    #expect(invalid == nil)
    let next = stick.process(x: 0, y: 1)
    #expect(next == .flick(degrees: 0))
  }
}
