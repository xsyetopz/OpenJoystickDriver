import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct DriverKitRelaySelfTestTests {
  @Test func diagnosticProbeIsBoundedAndEndsNeutral() {
    let reports = DextOutputDispatcher.diagnosticProbeReports(reportCount: 1_000)

    #expect(reports.count == 100)
    #expect(reports.allSatisfy { $0.count == GamepadHIDDescriptor.reportSize })
    #expect((reports[0][0] & 0x01) == 0x01)
    #expect(reports[reports.count - 1].allSatisfy { $0 == 0 })
  }

  @Test func ioRegistryDeliveryIsAuthoritative() {
    #expect(payload(inputDelta: 25).driverKitRelayVerdict == .passed)
    #expect(payload(inputDelta: 0, attempts: 26, successes: 26).driverKitRelayVerdict == .failed)
  }

  @Test func callbacksCanProveDeliveryWithoutRegistryCounters() {
    #expect(payload(reportEvents: 1).driverKitRelayVerdict == .passed)
    #expect(payload(valueEvents: 1).driverKitRelayVerdict == .passed)
    #expect(payload(inputDelta: 0, reportEvents: 1).driverKitRelayVerdict == .passed)
  }

  @Test func submissionWithoutDeliveryIsInconclusive() {
    #expect(payload(attempts: 26, successes: 26).driverKitRelayVerdict == .inconclusive)
  }

  @Test func missingOrRejectedSubmissionFails() {
    #expect(payload().driverKitRelayVerdict == .failed)
    #expect(payload(attempts: 26, successes: 0, failures: 26).driverKitRelayVerdict == .failed)
  }

  @Test func commandSuccessRequiresPassedRelayVerdict() {
    #expect(payload(inputDelta: 1).isSuccessful)
    #expect(!payload(inputDelta: 0, attempts: 26, successes: 26).isSuccessful)
    #expect(!payload(attempts: 26, successes: 26).isSuccessful)
    #expect(!payload(attempts: 26, failures: 26).isSuccessful)
  }

  @Test func requiredUserSpaceFailureControlsExitVerdict() {
    let denied = ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: 1,
      driverKitReportEvents: 0,
      userSpaceValueEvents: 20,
      userSpaceReportEvents: 20,
      userSpaceRequired: true,
      userSpaceStatus: "error: Accessibility denied"
    )
    #expect(denied.userSpaceVerdict == .failed)
    #expect(!denied.isSuccessful)

    let delivered = ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: 1,
      driverKitReportEvents: 0,
      userSpaceValueEvents: 1,
      userSpaceReportEvents: 0,
      userSpaceRequired: true,
      userSpaceStatus: "on"
    )
    #expect(delivered.userSpaceVerdict == .passed)
    #expect(delivered.isSuccessful)
  }

  @Test func cliAndGuiSurfaceTheSharedVerdict() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let service = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Service/ApplicationServiceServer/SelfTest.swift"
      ),
      encoding: .utf8
    )
    let command = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Commands/SelfTestCommand.swift"
      ),
      encoding: .utf8
    )
    let view = try String(
      contentsOf: root.appendingPathComponent(
        "Sources/OpenJoystickDriver/Views/MenuBarPopoverView/AdvancedCards.swift"
      ),
      encoding: .utf8
    )

    #expect(service.contains("dextDispatcher.sendDiagnosticProbe()"))
    #expect(command.contains("payload.driverKitRelayVerdict"))
    #expect(command.contains("payload.userSpaceVerdict"))
    #expect(command.contains("if !payload.isSuccessful { exit(1) }"))
    #expect(view.contains("t.driverKitRelayVerdict"))
  }

  private func payload(
    inputDelta: Int? = nil,
    reportEvents: Int = 0,
    valueEvents: Int = 0,
    attempts: Int? = nil,
    successes: Int? = nil,
    failures: Int? = nil
  ) -> ApplicationServiceVirtualDeviceSelfTestPayload {
    ApplicationServiceVirtualDeviceSelfTestPayload(
      seconds: 1,
      driverKitValueEvents: valueEvents,
      driverKitReportEvents: reportEvents,
      userSpaceValueEvents: 0,
      userSpaceReportEvents: 0,
      driverKitInputReportDelta: inputDelta,
      driverKitSetReportSuccessDelta: successes,
      driverKitSetReportAttemptDelta: attempts,
      driverKitSetReportFailureDelta: failures
    )
  }
}
