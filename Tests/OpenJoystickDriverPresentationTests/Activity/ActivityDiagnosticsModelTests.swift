import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityCheckRowTests {
  @Test
  func eachStatusMapsToItsLabelAndSymbol() {
    let rows = [
      ActivityCheckRow(DiagnoseCheck("service", .pass, "running 1.0")),
      ActivityCheckRow(DiagnoseCheck("usb-access", .warn, "USB scan failed")),
      ActivityCheckRow(DiagnoseCheck("input-read", .fail, "denied; grant it")),
      ActivityCheckRow(DiagnoseCheck("virtual-device", .skip, "service not running")),
    ]

    #expect(
      rows.map(\.statusKey) == [
        "ui.activity.status.pass", "ui.activity.status.warn", "status.failed",
        "ui.activity.status.skip",
      ]
    )
    #expect(Set(rows.map(\.symbolName)).count == 4)
  }

  @Test
  func rowKeepsCheckIdAndItsFixText() {
    let row = ActivityCheckRow(
      DiagnoseCheck("input-read", .fail, "denied; grant it with 'ojd permission request'")
    )

    #expect(row.id == "input-read")
    #expect(row.detail == "denied; grant it with 'ojd permission request'")
  }
}

@Suite
@MainActor
struct ActivityDiagnosticsModelTests {
  @Test
  func runPublishesOneRowPerCheckInOrder() async {
    let model = ActivityDiagnosticsModel {
      [DiagnoseCheck("service", .pass, "running"), DiagnoseCheck("usb-access", .warn, "none")]
    }
    #expect(model.state == .idle)

    await model.run()

    #expect(
      model.state
        == .finished([
          ActivityCheckRow(DiagnoseCheck("service", .pass, "running")),
          ActivityCheckRow(DiagnoseCheck("usb-access", .warn, "none")),
        ])
    )
    #expect(!model.isRunning)
  }

  @Test
  func runIfNeededRunsOnlyBeforeFirstResult() async {
    let runs = Locked(0)
    let model = ActivityDiagnosticsModel {
      runs.withLock { $0 += 1 }
      return []
    }

    await model.runIfNeeded()
    await model.runIfNeeded()
    await model.run()

    #expect(runs.withLock { $0 } == 2)
  }

  @Test
  func checkComposerKeepsReportOrderOfCommand() {
    let snapshot = DiagnoseServiceSnapshot(
      availability: .stopped,
      status: nil,
      virtualDiagnostics: nil,
      frameTimings: nil,
      listenerFailure: .absent
    )
    let checks = DiagnosticsService.checks(
      snapshot: snapshot,
      extensionStatus: ExtensionStatus(bundle: .present, registration: .active("record")),
      records: ControllerRecordSet.bundled,
      virtualDevices: [],
      usb: .success(2)
    )

    #expect(
      checks.map(\.id) == [
        "transport-extension-bundle", "transport-extension-registration", "service", "input-read",
        "input-inject", "virtual-device", "controller-records", "input-mapping",
        "switch-placeholder-serial", "config-files", "usb-access",
      ]
    )
  }
}
