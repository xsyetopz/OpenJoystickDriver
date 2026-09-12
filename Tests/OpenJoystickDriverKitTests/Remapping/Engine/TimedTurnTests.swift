import Testing
@testable import OpenJoystickDriverKit

struct TimedTurnTests {
  @Test func delayedAndRepeatedTicksDoNotChangeTotalTurn() {
    var turn = RemappingTimedTurn()
    let initial = turn.append(degrees: 90, durationNanoseconds: 100, at: 0)
    #expect(initial == 0)
    let first = turn.advance(at: 50)
    #expect(first == 45)
    let backward = turn.advance(at: 25)
    #expect(backward == 0)
    let late = turn.advance(at: 1000)
    #expect(late == 45)
    let repeated = turn.advance(at: 1000)
    #expect(repeated == 0)
    #expect(!turn.isActive)
  }

  @Test func overlappingTurnsRetainUnemittedMovement() {
    var turn = RemappingTimedTurn()
    _ = turn.append(degrees: 90, durationNanoseconds: 100, at: 0)
    let due = turn.append(degrees: 90, durationNanoseconds: 100, at: 50)
    let remaining = turn.advance(at: 150)
    #expect(due == 45)
    #expect(remaining == 135)
    #expect(!turn.isActive)
  }

  @Test func zeroDurationEmitsOnceAndResetCancels() {
    var turn = RemappingTimedTurn()
    let immediate = turn.append(degrees: -90, durationNanoseconds: 0, at: 0)
    #expect(immediate == -90)
    #expect(!turn.isActive)
    _ = turn.append(degrees: 180, durationNanoseconds: 100, at: 10)
    turn.reset()
    let cancelled = turn.advance(at: 1000)
    #expect(cancelled == 0)
  }
}
