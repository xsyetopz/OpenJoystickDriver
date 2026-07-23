import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct RemappingOutputSchedulerTests {
  @Test func enabledTickerRemainsDormantWhenIdleOrHoldingOrdinaryKey() async throws {
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
    _ = await yieldUntil { false }
    #expect(probe.sleepCount == 0)
    #expect(!harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(
      events: [.buttonPressed(.a)],
      from: remappingRouterDevice(1)
    )
    _ = await yieldUntil { false }
    #expect(probe.sleepCount == 0)
    #expect(!harness.router.tickerIsRunning)
  }

  @Test func turboStartsStopsAndReactivatesExactlyOneTicker() async throws {
    let probe = RemappingTickerProbe()
    let profile = remappingRouterProfile(
      turbo: RemappingTurbo(repeatRateHz: 10, dutyCycle: 0.25)
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
    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    #expect(await yieldUntil { probe.sleepCount == 1 })
    #expect(harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    _ = await yieldUntil { false }
    #expect(probe.sleepCount == 1)
    try await harness.router.dispatchCausally(events: [.buttonReleased(.a)], from: device)
    #expect(!harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(events: [.buttonPressed(.a)], from: device)
    #expect(await yieldUntil { probe.sleepCount == 2 })
    #expect(harness.router.tickerIsRunning)
  }

  @Test func tickerHonorsSixtyHertzFivePercentTurboDeadlines() async throws {
    let start: UInt64 = 1_000_000_000
    let clock = RemappingTickerClock(start)
    let probe = RemappingTickerProbe(clock: clock)
    let profile = remappingRouterProfile(
      turbo: RemappingTurbo(repeatRateHz: 60, dutyCycle: 0.05)
    )
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
      events: [.buttonPressed(.a)],
      from: remappingRouterDevice(1)
    )
    #expect(await yieldUntil { probe.sleepCount == 1 })
    #expect(probe.sleepDurations == [833_333])

    probe.resumeNext()
    #expect(await yieldUntil { probe.sleepCount == 2 })
    #expect(probe.sleepDurations == [833_333, 15_833_334])
    probe.resumeNext()
    #expect(await yieldUntil { harness.recorder.snapshot().count >= 3 })

    #expect(Array(harness.recorder.snapshot().prefix(3)) == [
      .system(.keyDown(.space)),
      .system(.keyUp(.space)),
      .system(.keyDown(.space)),
    ])
  }

  @Test func continuousOutputStartsTickerAndNeutralAxisStopsIt() async throws {
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
        ),
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
    try await harness.router.dispatchCausally(
      events: [.rightStickChanged(x: 0.75, y: 0)],
      from: device
    )
    #expect(await yieldUntil { probe.sleepCount == 1 })
    #expect(harness.router.tickerIsRunning)

    try await harness.router.dispatchCausally(
      events: [.rightStickChanged(x: 0, y: 0)],
      from: device
    )
    #expect(!harness.router.tickerIsRunning)
  }

}

private func yieldUntil(_ condition: @escaping @Sendable () -> Bool) async -> Bool {
  for _ in 0..<1_000 {
    if condition() { return true }
    await Task.yield()
  }
  return condition()
}
