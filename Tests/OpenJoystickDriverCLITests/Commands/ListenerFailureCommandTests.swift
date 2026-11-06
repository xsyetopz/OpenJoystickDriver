import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized, .removingTemporarySockets)
struct ListenerFailureCommandTests {
  private let failure = ServiceListenerFailure(
    errorNumber: EBADF,
    time: Date(timeIntervalSince1970: 1_800_000_000),
    process: .current
  )

  private func runStatus(_ arguments: [String], socketPath: String) async -> CLIRun {
    let records = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    return await RecordStore.$directory.withValue(records) {
      await ServiceConnection.$socketPath.withValue(socketPath) {
        await StatusCommand.$extensionProbe.withValue(
          { ExtensionStatus(bundle: .present, registration: .absent) },
          operation: { await CLIRun.run(["status"] + arguments) }
        )
      }
    }
  }

  private func runDiagnose(_ arguments: [String], socketPath: String) async -> CLIRun {
    let records = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    return await RecordStore.$directory.withValue(records) {
      await ServiceConnection.$socketPath.withValue(socketPath) {
        await StatusCommand.$extensionProbe.withValue(
          { ExtensionStatus(bundle: .present, registration: .active("enabled")) },
          operation: {
            await DiagnoseCommand.$usbProbe.withValue(
              { 1 },
              operation: {
                await DiagnoseCommand.$gameControllerAudit.withValue(
                  { nil },
                  operation: { await CLIRun.run(["diagnose"] + arguments + testServerTimeout) }
                )
              }
            )
          }
        )
      }
    }
  }

  private func service(_ run: CLIRun) throws -> [String: Any] {
    try #require(try run.json()["service"] as? [String: Any])
  }

  @Test
  func statusNamesTheStoppedListenerWhenTheServiceIsUnreachable() async throws {
    let socketPath = temporarySocketPath()
    try failure.write(socketPath: socketPath)
    defer { try? ServiceListenerFailure.clear(socketPath: socketPath) }

    let json = await runStatus(["--json"], socketPath: socketPath)
    let plain = await runStatus(["--plain"], socketPath: socketPath)
    let human = await runStatus([], socketPath: socketPath)

    // The report is printed, then the command fails with the code of the stopped listener.
    #expect(json.code == 69, "\(json.standardError)")
    #expect(json.standardError.contains("error[E2034]"))
    #expect(plain.code == 69)
    #expect(human.code == 69)
    let report = try service(json)
    #expect(report["state"] as? String == "Stopped")
    let listener = try #require(report["listenerFailure"] as? [String: Any])
    #expect(listener["code"] as? String == "E2034")
    #expect(listener["errno"] as? Int == Int(EBADF))
    #expect(listener["current"] as? Bool == true)
    #expect(
      (listener["message"] as? String)?.contains(
        ErrorCode.requestListenerStopped.localizedExplanation
      ) == true
    )
    #expect(plain.standardOutput.contains("listener-failure\tE2034\t\(EBADF)\t"))
    #expect(human.standardOutput.contains(failure.localizedSummary))
  }

  @Test
  func statusWithoutTheFileReportsNoListenerFailure() async throws {
    let json = await runStatus(["--json"], socketPath: temporarySocketPath())

    let report = try service(json)
    #expect(report["listenerFailure"] == nil)
    #expect(report["listenerFailureProblem"] == nil)
  }

  @Test
  func statusReportsAMalformedFileAsItsOwnProblem() async throws {
    let socketPath = temporarySocketPath()
    let path = ServiceListenerFailure.path(forSocket: socketPath)
    try Data("{\"apiVersion\":\"openjoystickdriver/v1alpha2\"}".utf8)
      .write(to: URL(fileURLWithPath: path))
    defer { try? FileManager.default.removeItem(atPath: path) }

    let json = await runStatus(["--json"], socketPath: socketPath)
    let human = await runStatus([], socketPath: socketPath)

    // A record that cannot be used fails with its own code, not the unreachable service's.
    #expect(json.code == 1, "\(json.standardError)")
    #expect(json.standardError.contains("error[E2035]"))
    let report = try service(json)
    #expect(report["listenerFailure"] == nil)
    let problem = try #require(report["listenerFailureProblem"] as? String)
    #expect(problem.contains(path))
    #expect(problem.contains("E2035"))
    #expect(human.standardOutput.contains(path))
  }

  @Test
  func diagnoseFailsTheServiceCheckWithTheListenerFailure() async throws {
    let socketPath = temporarySocketPath()
    try failure.write(socketPath: socketPath)
    defer { try? ServiceListenerFailure.clear(socketPath: socketPath) }

    let run = await runDiagnose(["--json"], socketPath: socketPath)

    let checks = try #require(try run.json()["checks"] as? [[String: String]])
    let check = try #require(checks.first { $0["id"] == "service" })
    #expect(check["status"] == "Fail")
    #expect(check["detail"] == failure.localizedSummary)
    #expect(check["detail"]?.contains("E2034") == true)
  }

  @Test
  func diagnoseFailsTheServiceCheckForAMalformedFile() async throws {
    let socketPath = temporarySocketPath()
    let path = ServiceListenerFailure.path(forSocket: socketPath)
    try Data("not json".utf8).write(to: URL(fileURLWithPath: path))
    defer { try? FileManager.default.removeItem(atPath: path) }

    let run = await runDiagnose(["--json"], socketPath: socketPath)

    let checks = try #require(try run.json()["checks"] as? [[String: String]])
    let check = try #require(checks.first { $0["id"] == "service" })
    #expect(check["status"] == "Fail")
    #expect(check["detail"]?.contains(path) == true)
  }

  @Test
  func aRecordOfAnEndedServiceInformsWithoutFailing() async throws {
    let socketPath = temporarySocketPath()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    let ended = ServiceListenerFailure(
      errorNumber: EBADF,
      time: Date(timeIntervalSince1970: 1_800_000_000),
      process: .init(identifier: process.processIdentifier, startSeconds: 1, startMicroseconds: 0)
    )
    try ended.write(socketPath: socketPath)
    defer { try? ServiceListenerFailure.clear(socketPath: socketPath) }

    let json = await runStatus(["--json"], socketPath: socketPath)
    let diagnose = await runDiagnose(["--json"], socketPath: socketPath)

    #expect(json.code == 0, "\(json.standardError)")
    let listener = try #require(try service(json)["listenerFailure"] as? [String: Any])
    #expect(listener["current"] as? Bool == false)
    #expect(listener["message"] as? String == ended.localizedEarlierSummary)
    let checks = try #require(try diagnose.json()["checks"] as? [[String: String]])
    let check = try #require(checks.first { $0["id"] == "service" })
    #expect(check["status"] == "Warn")
    #expect(check["detail"] == ended.localizedEarlierSummary)
  }
}
