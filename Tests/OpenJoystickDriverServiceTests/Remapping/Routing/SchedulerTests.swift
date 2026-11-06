import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverService

struct RemappingOutputSchedulerTests {
  @Test
  func enabledTickerRemainsDormantWhenIdleOrHoldingOrdinaryKey() async throws {
    let probe = RemappingTickerProbe()
    let harness = try await RemappingRouterHarness.make(
      profile: remappingRouterProfile(),
      tickerIntervalNanoseconds: 1,
      tickerSleeper: probe.sleep
    )
    defer {
      harness.router.stopTicker()
      probe.resumeAll()
      harness.removeFiles()
    }
    harness.router.startTicker()
    await letPendingWorkRun()
    #expect(probe.sleepCount == 0)
    #expect(!harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(
      changes: [.press(.south)],
      from: remappingRouterDevice(1)
    )
    await letPendingWorkRun()
    #expect(probe.sleepCount == 0)
    #expect(!harness.router.tickerIsRunning)
  }

  @Test
  func turboStartsStopsAndReactivatesExactlyOneTicker() async throws {
    let probe = RemappingTickerProbe()
    let profile = remappingRouterProfile(turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25))
    let harness = try await RemappingRouterHarness.make(
      profile: profile,
      tickerIntervalNanoseconds: 1,
      tickerSleeper: probe.sleep
    )
    defer {
      harness.router.stopTicker()
      probe.resumeAll()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    harness.router.startTicker()
    try await harness.router.dispatchCausally(changes: [.press(.south)], from: device)
    await waitUntil("probe.sleepCount == 1") { probe.sleepCount == 1 }
    #expect(harness.router.tickerIsRunning)

    // A repeated report of the held button starts no second ticker.
    try await harness.router.dispatchCausally(changes: [], from: device)
    await letPendingWorkRun()
    #expect(probe.sleepCount == 1)
    try await harness.router.dispatchCausally(changes: [.release(.south)], from: device)
    #expect(!harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(changes: [.press(.south)], from: device)
    await waitUntil("probe.sleepCount == 2") { probe.sleepCount == 2 }
    #expect(harness.router.tickerIsRunning)
  }

  @Test
  func tickerHonorsSixtyHertzFivePercentTurboDeadlines() async throws {
    let start: UInt64 = 1_000_000_000
    let clock = RemappingTickerClock(start)
    let probe = RemappingTickerProbe(clock: clock)
    let profile = remappingRouterProfile(turbo: RemappingTurbo(repeatRateHz: 60, dutyCycle: 0.05))
    let harness = try await RemappingRouterHarness.make(
      profile: profile,
      tickerIntervalNanoseconds: 8_000_000,
      tickerSleeper: probe.sleep,
      uptime: clock.read
    )
    defer {
      harness.router.stopTicker()
      probe.resumeAll()
      harness.removeFiles()
    }
    harness.router.startTicker()
    try await harness.router.dispatchCausally(
      changes: [.press(.south)],
      from: remappingRouterDevice(1)
    )
    await waitUntil("probe.sleepCount == 1") { probe.sleepCount == 1 }
    #expect(probe.sleepDurations == [833_333])

    probe.resumeNext()
    await waitUntil("probe.sleepCount == 2") { probe.sleepCount == 2 }
    #expect(probe.sleepDurations == [833_333, 15_833_334])
    probe.resumeNext()
    await waitUntil("harness.recorder.snapshot().count >= 3") {
      harness.recorder.snapshot().count >= 3
    }

    #expect(
      Array(harness.recorder.snapshot().prefix(3)) == [
        .system(.keyDown(.space)), .system(.keyUp(.space)), .system(.keyDown(.space)),
      ]
    )
  }

  @Test
  func continuousOutputStartsTickerAndNeutralAxisStopsIt() async throws {
    let probe = RemappingTickerProbe()
    let profile = RemappingProfile(
      name: "Pointer",
      device: RemappingDeviceScope(vendorID: 1118, productID: 654),
      applicationScope: .global,
      bindings: [
        RemappingBinding(
          source: .axis(.rightStickX),
          destination: .mouseMovement(.x),
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )
      ]
    )
    let harness = try await RemappingRouterHarness.make(
      profile: profile,
      tickerIntervalNanoseconds: 1,
      tickerSleeper: probe.sleep
    )
    defer {
      harness.router.stopTicker()
      probe.resumeAll()
      harness.removeFiles()
    }
    let device = remappingRouterDevice(1)
    harness.router.startTicker()
    try await harness.router.dispatchCausally(changes: [.rightStick(x: 0.75, y: 0)], from: device)
    await waitUntil("probe.sleepCount == 1") { probe.sleepCount == 1 }
    #expect(harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(changes: [.rightStick(x: 0, y: 0)], from: device)
    #expect(!harness.router.tickerIsRunning)
  }

}

/// Gives already-scheduled work many turns to run.
///
/// Callers assert that nothing happened, so no signal exists to wait on.
private func letPendingWorkRun() async {
  for _ in 0..<1_000 { await Task.yield() }
}
