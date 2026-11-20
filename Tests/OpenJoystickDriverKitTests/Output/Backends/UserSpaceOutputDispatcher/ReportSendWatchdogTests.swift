import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// A timer and a clock that a test moves by hand.
private final class ManualWatchdogTime: @unchecked Sendable {
  private let lock = NSLock()
  private var scheduled: [(delay: UInt64, fire: DeadlineTimer.Fire, cancelled: Bool)] = []
  private var clock: UInt64 = 0

  var timer: DeadlineTimer {
    DeadlineTimer { [self] delay, fire in
      let index = lock.withLock {
        scheduled.append((delay, fire, false))
        return scheduled.count - 1
      }
      return { [self] in lock.withLock { scheduled[index].cancelled = true } }
    }
  }

  var now: @Sendable () -> UInt64 { { [self] in lock.withLock { clock } } }

  /// The delays of every timer scheduled so far.
  var delays: [UInt64] { lock.withLock { scheduled.map(\.delay) } }

  func advance(by nanoseconds: UInt64) { lock.withLock { clock += nanoseconds } }

  /// Fires the latest timer that is still armed.
  func fireLatest() {
    let fire = lock.withLock { () -> DeadlineTimer.Fire? in
      guard let index = scheduled.lastIndex(where: { !$0.cancelled }) else { return nil }
      scheduled[index].cancelled = true
      return scheduled[index].fire
    }
    fire?()
  }
}

/// Counts the expiries of the watched sends.
private final class ExpiryTally: @unchecked Sendable {
  private let lock = NSLock()
  private var expired: [Int] = []
  var sends: [Int] { lock.withLock { expired } }
  func record(_ send: Int) -> @Sendable () -> Void {
    { [self] in lock.withLock { expired.append(send) } }
  }
}

struct ReportSendWatchdogTests {
  private static let deadline: UInt64 = 1_000

  private func makeWatchdog(_ time: ManualWatchdogTime) -> ReportSendWatchdog {
    ReportSendWatchdog(deadlineNanoseconds: Self.deadline, timer: time.timer, now: time.now)
  }

  @Test
  func streamOfFinishedSendsArmsOneTimer() {
    let time = ManualWatchdogTime()
    let tally = ExpiryTally()
    let watchdog = makeWatchdog(time)

    for send in 0..<100 {
      let watch = watchdog.begin(onExpire: tally.record(send))
      time.advance(by: 5)
      watchdog.end(watch)
    }

    #expect(time.delays == [Self.deadline])
    #expect(tally.sends.isEmpty)
  }

  @Test
  func sendThatOutlivesItsDeadlineExpires() {
    let time = ManualWatchdogTime()
    let tally = ExpiryTally()
    let watchdog = makeWatchdog(time)

    _ = watchdog.begin(onExpire: tally.record(0))
    time.advance(by: Self.deadline)
    time.fireLatest()

    #expect(tally.sends == [0])
  }

  @Test
  func timerFiringDuringLaterSendWaitsOutThatSendsRemainingTime() {
    let time = ManualWatchdogTime()
    let tally = ExpiryTally()
    let watchdog = makeWatchdog(time)
    watchdog.end(watchdog.begin(onExpire: tally.record(0)))
    time.advance(by: 400)
    _ = watchdog.begin(onExpire: tally.record(1))

    time.advance(by: 600)
    time.fireLatest()

    #expect(tally.sends.isEmpty)
    #expect(time.delays == [Self.deadline, 400])
    time.advance(by: 400)
    time.fireLatest()
    #expect(tally.sends == [1])
  }

  @Test
  func timerFiringWhileIdleDisarmsUntilNextSend() {
    let time = ManualWatchdogTime()
    let tally = ExpiryTally()
    let watchdog = makeWatchdog(time)
    watchdog.end(watchdog.begin(onExpire: tally.record(0)))

    time.advance(by: Self.deadline)
    time.fireLatest()
    #expect(time.delays == [Self.deadline])

    _ = watchdog.begin(onExpire: tally.record(1))
    #expect(time.delays == [Self.deadline, Self.deadline])
    #expect(tally.sends.isEmpty)
  }

  @Test
  func stoppedWatchdogExpiresNothing() {
    let time = ManualWatchdogTime()
    let tally = ExpiryTally()
    let watchdog = makeWatchdog(time)
    _ = watchdog.begin(onExpire: tally.record(0))

    watchdog.stop()
    time.advance(by: Self.deadline)
    time.fireLatest()

    #expect(tally.sends.isEmpty)
  }
}
