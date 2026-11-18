import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

@Suite(.serialized, .timeLimit(.minutes(1)))
struct VirtualFeedFeedbackWaitTests {
  /// A wait returns as soon as the host sends a command, long before its timeout, and the next
  /// exchange collects that command.
  @Test
  func waitReturnsWhenHostSendsCommand() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    let device = try #require(factory.devices.first)
    let started = Date()

    async let ready = registry.waitForFeedback(token: session.token, timeout: 30)
    try await Task.sleep(nanoseconds: 50_000_000)
    device.receive(.stopRumble)

    #expect(await ready)
    #expect(Date().timeIntervalSince(started) < 5)
    #expect(registry.exchange(token: session.token, frames: []).feedback == [.stopRumble])
  }

  @Test
  func waitWithCommandAlreadyQueuedReturnsAtOnce() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")
    try #require(factory.devices.first).receive(.stopRumble)

    #expect(await registry.waitForFeedback(token: session.token, timeout: 30))
  }

  @Test
  func waitWithNothingToReportReturnsFalseAfterTimeout() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")

    #expect(await registry.waitForFeedback(token: session.token, timeout: 0.05) == false)
  }

  @Test
  func waitReturnsTrueWhenFeedCloses() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")

    async let ready = registry.waitForFeedback(token: session.token, timeout: 30)
    try await Task.sleep(nanoseconds: 50_000_000)
    await registry.close(token: session.token)

    #expect(await ready)
  }

  @Test
  func cancelledWaitReturns() async throws {
    let factory = FakeFeedFactory()
    let registry = factory.registry()
    let session = try await registry.open(profile: "Generic")

    let wait = Task { await registry.waitForFeedback(token: session.token, timeout: 30) }
    wait.cancel()

    #expect(await wait.value == false)
  }
}
