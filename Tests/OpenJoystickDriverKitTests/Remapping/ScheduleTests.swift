import Testing

@testable import OpenJoystickDriverKit

struct RemappingScheduleTests {
  @Test
  func turboDeadlineHonorsSixtyHertzFivePercentDutyBoundaries() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink())
    let currentProfile = profile(bindings: [
      turboBinding(source: .button(.south), key: .a, rate: 60, duty: 0.05),
    ])
    let start: UInt64 = 1_000_000_000
    let offBoundary = start + 833_333
    let nextPeriod = start + 16_666_667

    #expect(await deadline(engine, after: start, cadence: 8_000_000) == nil)
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device,
      using: currentProfile,
      at: start
    )
    #expect(await deadline(engine, after: start, cadence: 8_000_000) == offBoundary)
    #expect(await deadline(engine, after: offBoundary, cadence: 8_000_000) == offBoundary)

    try await engine.tick(at: offBoundary)
    #expect(await deadline(engine, after: offBoundary, cadence: 8_000_000) == nextPeriod)
  }

  @Test
  func continuousAndMultipleTurboDeadlinesChooseTheEarliestWork() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink())
    let currentProfile = profile(bindings: [
      turboBinding(source: .button(.south), key: .a, rate: 10, duty: 0.5),
      turboBinding(source: .button(.east), key: .b, rate: 20, duty: 0.1),
      continuousBinding(),
    ])
    let start: UInt64 = 2_000_000_000

    try await engine.process(
      events: [.buttonPressed(.a), .buttonPressed(.b)],
      from: device,
      using: currentProfile,
      at: start
    )
    #expect(await deadline(engine, after: start, cadence: 8_000_000) == start + 5_000_000)

    try await engine.process(
      events: [.leftStickChanged(x: 0.8, y: 0)],
      from: device,
      using: currentProfile,
      at: start
    )
    #expect(await deadline(engine, after: start, cadence: 1_000_000) == start + 1_000_000)

    try await engine.process(
      events: [.buttonReleased(.a), .buttonReleased(.b), .leftStickChanged(x: 0, y: 0)],
      from: device,
      using: currentProfile,
      at: start
    )
    #expect(await deadline(engine, after: start, cadence: 1_000_000) == nil)
  }

  @Test
  func scheduledDeadlineSaturatesAndReleasePathsReturnNil() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink())
    let currentProfile = profile(bindings: [continuousBinding(destination: .scroll(.x))])

    try await activateContinuous(engine, profile: currentProfile)
    #expect(await deadline(engine, after: .max - 4, cadence: 8) == .max)
    try await engine.releaseAll(for: device)
    #expect(await deadline(engine, after: 0, cadence: 8) == nil)

    try await activateContinuous(engine, profile: currentProfile)
    try await engine.setProfile(nil, for: device)
    #expect(await deadline(engine, after: 0, cadence: 8) == nil)

    try await activateContinuous(engine, profile: currentProfile)
    try await engine.drain()
    #expect(await deadline(engine, after: 0, cadence: 8) == nil)
  }

  @Test
  func scheduledWorkExcludesOrdinaryHeldKeysAndMouseButtons() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink())
    let currentProfile = profile(bindings: [
      RemappingBinding(
        source: .button(.east),
        destination: .keyboard(key: .b, modifiers: [])
      ),
      RemappingBinding(
        source: .button(.west),
        destination: .mouseButton(.right)
      ),
      turboBinding(source: .button(.south), key: .a, rate: 10, duty: 0.5),
    ])

    #expect(await engine.hasScheduledOutput() == false)
    try await engine.process(
      events: [.buttonPressed(.b), .buttonPressed(.x)],
      from: device,
      using: currentProfile,
      at: 0
    )
    #expect(await engine.hasScheduledOutput() == false)
    try await engine.process(
      events: [.buttonPressed(.a)],
      from: device,
      using: currentProfile,
      at: 1
    )
    #expect(await engine.hasScheduledOutput())
    try await engine.process(
      events: [.buttonReleased(.a)],
      from: device,
      using: currentProfile,
      at: 2
    )
    #expect(await engine.hasScheduledOutput() == false)
  }

  @Test
  func continuousSchedulingStopsAtNeutralAndEveryReleaseLifecycle() async throws {
    let engine = RemappingEventEngine(sink: RemappingTestSink())
    let currentProfile = profile(bindings: [continuousBinding()])

    #expect(await engine.hasScheduledOutput() == false)
    try await activateContinuous(engine, profile: currentProfile)
    try await engine.process(
      events: [.leftStickChanged(x: 0, y: 0)],
      from: device,
      using: currentProfile,
      at: 1
    )
    #expect(await engine.hasScheduledOutput() == false)

    try await activateContinuous(engine, profile: currentProfile)
    try await engine.releaseAll(for: device)
    #expect(await engine.hasScheduledOutput() == false)

    try await activateContinuous(engine, profile: currentProfile)
    try await engine.setProfile(nil, for: device)
    #expect(await engine.hasScheduledOutput() == false)

    try await activateContinuous(engine, profile: currentProfile)
    try await engine.drain()
    #expect(await engine.hasScheduledOutput() == false)
  }

  private var device: DeviceIdentifier {
    DeviceIdentifier(vendorID: 1, productID: 2, locationID: 1)
  }

  private func deadline(
    _ engine: RemappingEventEngine,
    after uptimeNanoseconds: UInt64,
    cadence: UInt64
  ) async -> UInt64? {
    await engine.nextScheduledTick(
      after: uptimeNanoseconds,
      continuousIntervalNanoseconds: cadence
    )
  }

  private func profile(bindings: [RemappingBinding]) -> RemappingProfile {
    RemappingProfile(
      name: "Schedule",
      device: RemappingDeviceScope(vendorID: 1, productID: 2),
      applicationScope: .global,
      bindings: bindings
    )
  }

  private func turboBinding(
    source: RemappingSource,
    key: RemappingKeyboardKey,
    rate: Double,
    duty: Double
  ) -> RemappingBinding {
    RemappingBinding(
      source: source,
      destination: .keyboard(key: key, modifiers: []),
      turbo: RemappingTurbo(repeatRateHz: rate, dutyCycle: duty)
    )
  }

  private func continuousBinding(
    destination: RemappingDestination = .mouseMovement(.x)
  ) -> RemappingBinding {
    RemappingBinding(
      source: .axis(.leftStickX),
      destination: destination,
      axisTuning: .default
    )
  }

  private func activateContinuous(
    _ engine: RemappingEventEngine,
    profile: RemappingProfile
  ) async throws {
    try await engine.process(
      events: [.leftStickChanged(x: 0.8, y: 0)],
      from: device,
      using: profile,
      at: 0
    )
    #expect(await engine.hasScheduledOutput())
  }
}
