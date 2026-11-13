import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

@Suite(.serialized)
struct TransportExtensionCommandTests {
  private func status(_ arguments: [String], _ extensionStatus: ExtensionStatus) async -> CLIRun {
    let probe: @Sendable () -> ExtensionStatus = { extensionStatus }
    return await StatusCommand.$extensionProbe.withValue(probe) {
      await CLIRun.run(["transport-extension", "status"] + arguments)
    }
  }

  private func submit(
    _ verb: String,
    _ arguments: [String] = [],
    outcome: SystemExtensionSetupRequestResult,
    actions: Locked<[TransportExtensionSubmission.Action]> = Locked([])
  ) async -> CLIRun {
    let submission:
      @Sendable (TransportExtensionSubmission.Action) async ->
        SystemExtensionSetupRequestResult = {
          action in
          actions.withLock { $0.append(action) }
          return outcome
        }
    return await TransportExtensionSubmission.$submit.withValue(submission) {
      await CLIRun.run(["transport-extension", verb] + arguments)
    }
  }

  @Test
  func statusPrintsBundleAndRegistrationAsJSONAndPlainRows() async throws {
    let active = ExtensionStatus(bundle: .present, registration: .active("record line"))

    let jsonRun = await status(["--json"], active)
    let plainRun = await status(["--plain"], active)

    #expect(jsonRun.code == 0)
    let json = try jsonRun.json()
    #expect(json["bundle"] as? String == "Present")
    #expect(json["registration"] as? String == "Active")
    #expect(json["detail"] as? String == "record line")
    #expect(plainRun.standardOutput == "bundle\tpresent\nregistration\tactive\n")
  }

  @Test
  func statusOmitsDetailWhenThereIsNone() async throws {
    let result = await status(["--json"], ExtensionStatus(bundle: .missing, registration: .absent))

    #expect(result.code == 0)
    let json = try result.json()
    #expect(json["bundle"] as? String == "Missing")
    #expect(json["registration"] as? String == "Absent")
    #expect(json["detail"] == nil)
  }

  @Test
  func statusPrintsHumanRowsAndRegistrationRecord() async {
    let result = await status(
      [],
      ExtensionStatus(bundle: .present, registration: .inactive("record line"))
    )

    #expect(result.code == 0)
    let lines = result.standardOutput.split(separator: "\n")
    #expect(lines.count == 3)
    #expect(lines[0].hasSuffix("  present"))
    #expect(lines[1].hasSuffix("  inactive"))
    #expect(lines[2] == "record line")
  }

  @Test
  func statusExitsOneWhenMacOSDoesNotReportRegistration() async {
    let result = await status(
      ["--plain"],
      ExtensionStatus(bundle: .present, registration: .unavailable("probe failed"))
    )

    #expect(result.code == 1)
    #expect(result.standardOutput == "bundle\tpresent\nregistration\tunavailable\n")
    #expect(result.standardError.hasPrefix("error[E2015]: "))
    #expect(result.standardError.contains("probe failed"))
  }

  @Test
  func activateReportsStateAndSubmitsOneActivation() async throws {
    let actions = Locked<[TransportExtensionSubmission.Action]>([])

    let jsonRun = await submit("activate", ["--json"], outcome: .active, actions: actions)
    let humanRun = await submit("activate", outcome: .active, actions: actions)

    #expect(try jsonRun.json()["state"] as? String == "Active")
    #expect(humanRun.code == 0)
    #expect(humanRun.standardOutput.isEmpty)
    #expect(humanRun.standardError.split(separator: "\n").count == 1)
    #expect(actions.withLock { $0 } == [.activate, .activate])
  }

  @Test
  func deactivateSubmitsDeactivation() async throws {
    let actions = Locked<[TransportExtensionSubmission.Action]>([])

    let result = await submit("deactivate", ["--plain"], outcome: .inactive, actions: actions)
    let jsonRun = await submit("deactivate", ["--json"], outcome: .inactive, actions: actions)

    #expect(result.code == 0)
    #expect(result.standardOutput == "state\tinactive\n")
    #expect(try jsonRun.json()["state"] as? String == "Inactive")
    #expect(actions.withLock { $0 } == [.deactivate, .deactivate])
  }

  @Test
  func activateWaitingForApprovalExitsZeroAndSaysWhereToApprove() async throws {
    let human = await submit("activate", outcome: .awaitingApproval)
    let quiet = await submit("activate", ["--quiet"], outcome: .awaitingApproval)
    let json = await submit("activate", ["--json"], outcome: .awaitingApproval)

    #expect(human.code == 0)
    #expect(!human.standardError.isEmpty)
    #expect(!quiet.standardError.isEmpty)
    #expect(try json.json()["state"] as? String == "AwaitingApproval")
  }

  @Test(arguments: [
    SystemExtensionSetupRequestResult.failed(
      SystemExtensionRequestFailure(domain: "OSSystemExtensionErrorDomain", code: 4, text: "x")
    ), .timedOut,
  ])
  func activateThatMacOSRejectsOrDoesNotFinishExitsOne(
    outcome: SystemExtensionSetupRequestResult
  ) async {
    let result = await submit("activate", outcome: outcome)

    #expect(result.code == 1)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error[E2015]: "))
    #expect(result.standardError.contains("ojd transport-extension status"))
  }
}
