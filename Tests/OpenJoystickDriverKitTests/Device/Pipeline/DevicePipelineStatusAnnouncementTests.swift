import Foundation
import Testing

@testable import OpenJoystickDriverKit

/// Each status the pipeline reports in `getStatus` announces its change from the pipeline itself.
@Suite(.timeLimit(.minutes(1)))
struct DevicePipelineStatusAnnouncementTests {
  private final class Posts: @unchecked Sendable {
    private let lock = NSLock()
    private var posts = 0
    var count: Int { lock.withLock { posts } }
    func increment() { lock.withLock { posts += 1 } }
  }

  private final class PowerDriver: PhysicalProtocolDriver, @unchecked Sendable {
    let capabilities = ControllerCapabilities(controls: Control.xboxLayout)
    let sessionPlan: DriverSessionPlan
    init(livenessTimeoutNanoseconds: UInt64 = 60_000_000) {
      sessionPlan = DriverSessionPlan(
        inputReportLivenessTimeoutNanoseconds: livenessTimeoutNanoseconds
      )
    }
    let outputCapabilities = PhysicalControllerOutputCapabilities.none
    let defaultColor: ControllerColor? = nil
    private let lock = NSLock()
    private var stored: ControllerConnectionState.Power?
    var power: ControllerConnectionState.Power? {
      get { lock.withLock { stored } }
      set { lock.withLock { stored = newValue } }
    }
    func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

    /// Report 1 pushes the right stick, any other report centers it.
    func parse(report data: Data, receivedAt: MonotonicTimestamp) -> ControllerEvent? {
      ControllerEvent(data.first == 1 ? [.rightStick(x: 1, y: 0)] : [], at: receivedAt.nanoseconds)
    }
  }

  private func makePipeline(
    _ driver: PowerDriver,
    uptime: (@Sendable () -> UInt64)? = nil
  ) -> DevicePipeline {
    DevicePipeline(
      identifier: LogicalControllerID(vendorID: 1, productID: 2),
      transport: .hid(address: .ioKit(locationID: 9, interfaceNumber: nil)),
      driver: driver,
      dispatcher: ControllerSessionOutputProbe(),
      uptimeNanoseconds: uptime ?? { DispatchTime.now().uptimeNanoseconds }
    )
  }

  private func observe(_ pipeline: DevicePipeline) -> (Posts, any NSObjectProtocol) {
    let posts = Posts()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: pipeline,
      queue: nil
    ) { _ in posts.increment() }
    return (posts, observer)
  }

  @Test
  func changedPowerAnnouncesOnceAndSamePowerAnnouncesNothing() async {
    let driver = PowerDriver()
    let pipeline = makePipeline(driver)
    let (posts, observer) = observe(pipeline)
    defer { NotificationCenter.default.removeObserver(observer) }

    driver.power = ControllerConnectionState.Power(
      charging: .charging,
      battery: BatteryLevel(percentage: 80...80),
      wiredPower: nil
    )
    await pipeline.snapshotPower()
    #expect(posts.count == 1)
    await pipeline.snapshotPower()
    #expect(posts.count == 1)
  }

  @Test
  func changedStartupStatusAnnouncesOnce() async {
    let pipeline = makePipeline(PowerDriver())
    let (posts, observer) = observe(pipeline)
    defer { NotificationCenter.default.removeObserver(observer) }

    await pipeline.setStartupOutputStatusForTesting("succeeded")
    await pipeline.setStartupOutputStatusForTesting("succeeded")

    #expect(posts.count == 1)
  }

  @Test
  func changedInputConnectionAnnouncesOnce() async {
    let pipeline = makePipeline(PowerDriver())
    let (posts, observer) = observe(pipeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    let active = await pipeline.inputConnectionActive

    await pipeline.setInputConnectionActiveForTesting(!active)
    await pipeline.setInputConnectionActiveForTesting(!active)

    #expect(posts.count == 1)
  }

  @Test
  func overdueInputReportsAnnounceWithoutAnyEvent() async {
    let pipeline = makePipeline(PowerDriver())
    let (posts, observer) = observe(pipeline)
    defer { NotificationCenter.default.removeObserver(observer) }

    await pipeline.start()
    let deadline = Date().addingTimeInterval(30)
    while posts.count < 1, Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
    await pipeline.stop()

    #expect(posts.count >= 1)
  }

  @Test
  func oneRecoveryAnnouncesOnce() async {
    let clock = ManualUptime()
    let pipeline = makePipeline(
      PowerDriver(livenessTimeoutNanoseconds: 1_000_000_000),
      uptime: clock.now
    )
    let (posts, observer) = observe(pipeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    await pipeline.start()
    // Live input before the gap makes the gap a loss that the next neutral report recovers.
    await pipeline.feedHIDData(Data([2]))
    clock.advance(by: 2_000_000_000)
    // The overdue watch announces once the gap passes. The idle monitor can post the same gap
    // first, so the wait is for the watch itself to finish.
    let deadline = Date().addingTimeInterval(30)
    while await pipeline.staleWatchTask != nil, Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(posts.count >= 1)
    // The overdue gap retires output: the first report lands in the waiting-for-neutral state.
    await pipeline.feedHIDData(Data([1]))
    let before = posts.count

    await pipeline.feedHIDData(Data([2]))

    #expect(await pipeline.inputHealthRecoveryCount == 1)
    #expect(posts.count == before + 1)
    await pipeline.stop()
  }
}

extension DevicePipeline {
  func setStartupOutputStatusForTesting(_ status: String?) {
    startupOutputStatus = status
  }

  func setInputConnectionActiveForTesting(_ active: Bool) {
    inputConnectionActive = active
  }
}
