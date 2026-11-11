import ArgumentParser
import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct SettingTestNotificationCommandTests {
  /// A service that answers `sendTestNotification` with `outcome` after `answerDelay` and records
  /// its methods.
  private func serve(
    outcome: TestNotificationOutcome,
    socketPath: String,
    received: Locked<[String]> = Locked([]),
    answerDelay: Duration = .zero
  ) throws -> LocalServiceRPCServer {
    let server = LocalServiceRPCServer(
      socketPath: socketPath,
      authentication: { _ in true },
      handler: { request in
        received.withLock { $0.append(request.method) }
        guard request.method == ApplicationServiceRPCMethod.sendTestNotification.rawValue else {
          return LocalServiceRPCResponse(result: nil, error: "unexpected \(request.method)")
        }
        try? await Task.sleep(for: answerDelay)
        return LocalServiceRPCResponse(result: try? JSONEncoder().encode(outcome), error: nil)
      }
    )
    try server.start()
    return server
  }

  /// Runs the command with `timeout`, which is `testServerTimeout` unless a test passes `[]` to
  /// leave the default deadline.
  private func run(
    _ arguments: [String],
    socketPath: String,
    timeout: [String] = testServerTimeout
  ) async -> CLIRun {
    await ServiceConnection.$socketPath.withValue(socketPath) {
      await CLIRun.run(["setting", "test-notification"] + arguments + timeout)
    }
  }

  @Test
  func withoutTimeoutTheCommandWaitsForAnAnswerSlowerThanTheRequestDeadline() async throws {
    let socketPath = temporarySocketPath()
    let delay = Duration.milliseconds(800)
    #expect(delay > .seconds(ServiceTimeouts.request))
    let server = try serve(outcome: .shown, socketPath: socketPath, answerDelay: delay)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath, timeout: [])

    #expect(result.code == 0, "\(result.standardError)")
    #expect(
      result.standardError.contains(CLILocalized.text("cli.setting.testNotification.success"))
    )
  }

  /// The seconds as the help and the wiki write them.
  private static func seconds(_ value: Double) -> String { unsafe String(format: "%g", value) }

  @Test
  func theHelpNamesTheDefaultDeadlineFromServiceTimeouts() {
    let discussion = SettingTestNotificationCommand.configuration.discussion

    #expect(discussion.contains(Self.seconds(ServiceTimeouts.testNotification)))
    #expect(!discussion.contains("%@"))
  }

  @Test
  func theWikiNamesTheDeadlinesFromServiceTimeouts() throws {
    let repository = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let page = try String(
      contentsOf: repository.appendingPathComponent("wiki/Command-Reference.md"),
      encoding: .utf8
    )
    let pickup = Self.seconds(TestNotificationDeadlines.pickupSeconds)
    let answer = Self.seconds(TestNotificationDeadlines.answerSeconds)
    let reply = Self.seconds(
      ServiceTimeouts.testNotification - TestNotificationDeadlines.pickupSeconds
        - TestNotificationDeadlines.answerSeconds
    )
    let total = Self.seconds(ServiceTimeouts.testNotification)

    #expect(page.contains("no app taking it within \(pickup) seconds"))
    #expect(page.contains("not reporting within \(answer) seconds"))
    #expect(
      page.contains(
        "waits up to \(total) seconds for the service's answer, the \(pickup) and the \(answer) "
          + "plus \(reply) for the reply"
      )
    )
  }

  @Test
  func aShownNotificationSucceedsInEachFormat() async throws {
    let socketPath = temporarySocketPath()
    let received = Locked<[String]>([])
    let server = try serve(outcome: .shown, socketPath: socketPath, received: received)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let plain = await run(["--plain"], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 0, "\(human.standardError)")
    #expect(human.standardOutput.isEmpty)
    #expect(human.standardError.contains(CLILocalized.text("cli.setting.testNotification.success")))
    #expect(plain.standardOutput == "shown\n")
    #expect(try json.details()["outcome"] as? String == "Shown")
    #expect(
      received.withLock {
        $0 == Array(repeating: ApplicationServiceRPCMethod.sendTestNotification.rawValue, count: 3)
      }
    )
  }

  @Test
  func noAnswerFailsWithE2036() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .noAnswer, socketPath: socketPath)
    defer { server.stop() }

    let human = await run([], socketPath: socketPath)
    let json = await run(["--json"], socketPath: socketPath)

    #expect(human.code == 69)
    #expect(
      human.standardError
        == CLIFailure(.noApplicationAnswered, CLILocalized.text("error.E2036.message")).line + "\n"
    )
    #expect(human.standardOutput.isEmpty)
    #expect(json.code == 69)
    #expect(json.standardOutput.isEmpty)
  }

  @Test
  func deniedNotificationsFailWithE2037AndExit77() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .denied, socketPath: socketPath)
    defer { server.stop() }

    let result = await run(["--json"], socketPath: socketPath)

    #expect(result.code == 77)
    #expect(
      result.standardError
        == CLIFailure(.notificationsDenied, CLILocalized.text("error.E2037.message")).line + "\n"
    )
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func aFailedDeliveryNamesTheSystemsReason() async throws {
    let socketPath = temporarySocketPath()
    let server = try serve(outcome: .failed("the system refused"), socketPath: socketPath)
    defer { server.stop() }

    let result = await run([], socketPath: socketPath)

    #expect(result.code == 1)
    #expect(result.standardError.hasPrefix("error[E2006]: "))
    #expect(result.standardError.contains("the system refused"))
  }

  @Test
  func aStoppedServiceFailsWithE2004() async {
    let result = await run([], socketPath: temporarySocketPath())

    #expect(result.code == 69)
    #expect(result.standardError == CLIFailure.serviceUnavailable.line + "\n")
  }
}
