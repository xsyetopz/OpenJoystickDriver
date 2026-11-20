import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// A permission whose answer a test sets, with a clock and a refresh queue the test runs by hand.
private final class ManualPermission: CoreGraphicsPostEventAccessProbing, @unchecked Sendable {
  private let lock = NSLock()
  private var answer: Bool
  private var clock: UInt64 = 0
  private var queued: [@Sendable () -> Void] = []
  private(set) var preflights = 0
  /// Runs once inside the next preflight, after it read the answer.
  var duringNextPreflight: (() -> Void)?

  init(granted: Bool) { answer = granted }

  func preflight() -> Bool {
    let (granted, hook) = lock.withLock {
      preflights += 1
      defer { duringNextPreflight = nil }
      return (answer, duringNextPreflight)
    }
    hook?()
    return granted
  }

  func request() -> Bool { true }

  func set(granted: Bool) { lock.withLock { answer = granted } }

  func advance(by nanoseconds: UInt64) { lock.withLock { clock += nanoseconds } }

  var now: @Sendable () -> UInt64 { { [self] in lock.withLock { clock } } }

  var schedule: @Sendable (@escaping @Sendable () -> Void) -> Void {
    { [self] work in lock.withLock { queued.append(work) } }
  }

  /// Runs the refreshes queued so far.
  func runQueued() {
    let work = lock.withLock {
      defer { queued.removeAll() }
      return queued
    }
    for refresh in work { refresh() }
  }

  func cache(maxAge: UInt64) -> CachedPostEventAccessProbe {
    CachedPostEventAccessProbe(
      source: self,
      maxAgeNanoseconds: maxAge,
      now: now,
      schedule: schedule
    )
  }
}

struct CachedPostEventAccessProbeTests {
  @Test
  func preflightsWithinMaxAgeReadThePermissionOnce() {
    let permission = ManualPermission(granted: true)
    let cache = permission.cache(maxAge: 1_000)

    let answers = (0..<500).map { _ in cache.preflight() }

    #expect(answers.allSatisfy { $0 })
    #expect(permission.preflights == 1)
  }

  @Test
  func stalePreflightAnswersAtOnceAndRefreshesOffThread() {
    let permission = ManualPermission(granted: true)
    let cache = permission.cache(maxAge: 1_000)
    _ = cache.preflight()
    permission.set(granted: false)
    permission.advance(by: 1_000)

    let staleAnswer = cache.preflight()
    let readsBeforeRefresh = permission.preflights
    permission.runQueued()

    #expect(staleAnswer)
    #expect(readsBeforeRefresh == 1)
    #expect(!cache.preflight())
    #expect(permission.preflights == 2)
  }

  @Test
  func stalePreflightsScheduleOneRefresh() {
    let permission = ManualPermission(granted: true)
    let cache = permission.cache(maxAge: 1_000)
    _ = cache.preflight()
    permission.advance(by: 5_000)

    for _ in 0..<10 { _ = cache.preflight() }
    permission.runQueued()

    #expect(permission.preflights == 2)
  }

  @Test
  func requestMakesTheNextPreflightReadThePermission() {
    let permission = ManualPermission(granted: false)
    let cache = permission.cache(maxAge: 1_000)
    _ = cache.preflight()
    permission.set(granted: true)

    cache.request()

    #expect(cache.preflight())
    #expect(permission.preflights == 2)
  }

  @Test
  func refreshReadingAcrossARequestKeepsTheAnswerReadAfterIt() {
    let permission = ManualPermission(granted: false)
    let cache = permission.cache(maxAge: 1_000)
    _ = cache.preflight()
    permission.advance(by: 1_000)
    _ = cache.preflight()
    permission.duringNextPreflight = {
      cache.request()
      permission.set(granted: true)
      _ = cache.preflight()
    }

    permission.runQueued()

    #expect(cache.preflight())
    #expect(permission.preflights == 3)
  }
}
