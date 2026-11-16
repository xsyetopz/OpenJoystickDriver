import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverPresentation

@Suite
struct ActivityCheckKindTests {
  /// Every check that `DiagnosticsService.checks` can produce, whatever its status.
  private static func producedIDs() -> Set<String> {
    let stopped = DiagnoseServiceSnapshot(
      availability: .stopped,
      status: nil,
      virtualDiagnostics: nil,
      frameTimings: nil,
      listenerFailure: .absent
    )
    return Set(
      DiagnosticsService.checks(
        snapshot: stopped,
        extensionStatus: ExtensionStatus(bundle: .present, registration: .active("record")),
        records: ControllerRecordSet.bundled,
        virtualDevices: [],
        usb: .success(0)
      ).map(\.id)
    )
  }

  @Test
  func everyCheckHasNameAndGUIActionOrExplicitNone() {
    let listed = Set(ActivityCheckKind.all.map(\.id))

    #expect(listed == Self.producedIDs())
    #expect(listed.count == ActivityCheckKind.all.count)
    for kind in ActivityCheckKind.all {
      #expect(OJDLocalized.string(kind.nameKey) != kind.nameKey)
    }
  }

  @Test
  func fixButtonShowsOnlyForWarningOrFailureWithGUIAction() {
    let denied = ActivityCheckRow(DiagnoseCheck("input-read", .fail, "denied"))
    let granted = ActivityCheckRow(DiagnoseCheck("input-read", .pass, "granted"))
    let skipped = ActivityCheckRow(DiagnoseCheck("input-read", .skip, "service not running"))
    let stopped = ActivityCheckRow(DiagnoseCheck("service", .warn, "not running"))

    #expect(denied.fix == .requestInputRead)
    #expect(granted.fix == nil)
    #expect(skipped.fix == nil)
    #expect(stopped.fix == nil)
  }

  @Test
  func eachFixHasTitle() {
    let fixes: [ActivityCheckFix] = [
      .requestInputRead, .requestInputInject, .approveDriver, .showLibrary,
    ]
    for fix in fixes { #expect(OJDLocalized.string(fix.titleKey) != fix.titleKey) }
  }
}

@Suite
@MainActor
struct ActivityLogOrderTests {
  @Test
  func rowsListNewestLineFirstAndCopyKeepsWrittenOrder() {
    let model = ActivityLogModel(
      source: ActivityLogSource(
        tail: { stream, _ in
          ApplicationServiceLogSnapshot(
            stream: stream,
            path: "/tmp/log",
            exists: true,
            fileSizeBytes: 1,
            lines: stream == .standardOutput ? ["first", "second"] : [],
            truncated: false
          )
        },
        follow: { _, _ in AsyncStream { $0.finish() } }
      )
    )
    model.start()

    #expect(model.rows.map(\.text) == ["second", "first"])
    #expect(model.copyText == "first\nsecond")
    model.stop()
  }
}
