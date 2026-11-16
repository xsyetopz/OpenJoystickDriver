import Testing

@testable import OpenJoystickDriverPresentation

@MainActor
@Suite
struct RunLoopCoalescerTests {
  @Test
  func manySchedulesBeforeDeferredTurnRunActionOnce() {
    var turns: [@MainActor () -> Void] = []
    var runs = 0
    let coalescer = RunLoopCoalescer(deferring: { turns.append($0) }, action: { runs += 1 })

    coalescer.schedule()
    coalescer.schedule()
    coalescer.schedule()
    #expect(turns.count == 1)
    #expect(runs == 0)

    turns.removeFirst()()
    #expect(runs == 1)
  }

  @Test
  func scheduleAfterTurnRunsAgain() {
    var turns: [@MainActor () -> Void] = []
    var runs = 0
    let coalescer = RunLoopCoalescer(deferring: { turns.append($0) }, action: { runs += 1 })

    coalescer.schedule()
    turns.removeFirst()()
    coalescer.schedule()
    turns.removeFirst()()
    #expect(runs == 2)
  }
}
