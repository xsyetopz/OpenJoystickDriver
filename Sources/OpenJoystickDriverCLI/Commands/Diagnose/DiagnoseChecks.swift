import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

extension DiagnoseServiceSnapshot {
  /// Asks the service once; a stopped or failing service never throws.
  static func fetch() async -> Self {
    do {
      let (status, diagnostics) = try await ServiceConnection.request { client in
        let status = try await client.getStatus()
        return (status, try? await client.getVirtualDeviceDiagnostics())
      }
      return Self(availability: .running, status: status, virtualDiagnostics: diagnostics)
    } catch let failure as CLIFailure where failure.code == .serviceUnavailable {
      return Self(availability: .stopped, status: nil, virtualDiagnostics: nil)
    } catch {
      let message = (error as? CLIFailure)?.message ?? error.localizedDescription
      return Self(availability: .failed(message), status: nil, virtualDiagnostics: nil)
    }
  }
}

/// The soak options of `ojd diagnose --soak`.
struct DiagnoseSoak: Sendable, Equatable {
  let seconds: Int
  let intervalMilliseconds: Int
  let residentLimitMiB: Int
  let footprintLimitMiB: Int
}

enum DiagnoseChecks {
  /// Every check in report order.
  static func run(
    snapshot: DiagnoseServiceSnapshot,
    extensionStatus: ExtensionStatus,
    soak: DiagnoseSoak?
  ) async -> [DiagnoseCheck] {
    var checks = DiagnosticsService.extensionChecks(extensionStatus)
    checks.append(DiagnosticsService.serviceCheck(snapshot))
    checks.append(contentsOf: DiagnosticsService.permissionChecks(snapshot))
    checks.append(DiagnosticsService.virtualDeviceCheck(snapshot))
    checks.append(DiagnosticsService.recordCheck(RecordStore.load()))
    checks.append(await usbCheck())
    checks.append(await soakCheck(snapshot: snapshot, soak: soak))
    return checks
  }

  private static func usbCheck() async -> DiagnoseCheck {
    do {
      return DiagnosticsService.usbCheck(.success(try await DiagnoseCommand.usbProbe()))
    } catch {
      return DiagnosticsService.usbCheck(.failure(error))
    }
  }

  private static func soakCheck(
    snapshot: DiagnoseServiceSnapshot,
    soak: DiagnoseSoak?
  ) async -> DiagnoseCheck {
    let id = "runtime-health"
    guard let soak else {
      return DiagnoseCheck(
        id,
        .skip,
        CLILocalized.text("cli.diagnose.soak.not_requested")
      )
    }
    guard snapshot.availability == .running, let processID = ServiceConnection.processIdentifier()
    else { return DiagnosticsService.skipped(id, snapshot) }
    let policy = RuntimeHealthPolicy(
      residentLimitMiB: soak.residentLimitMiB,
      footprintLimitMiB: soak.footprintLimitMiB
    )
    CLIOutput.stderr(
      CLILocalized.format(
        "cli.diagnose.soak.progress",
        Double(soak.seconds).durationText
      )
    )
    do {
      let summary = try await DiagnoseCommand.soakSampler(
        processID,
        soak.seconds,
        soak.intervalMilliseconds,
        policy
      )
      return DiagnosticsService.soakCheck(summary)
    } catch { return DiagnoseCheck(id, .fail, error.localizedDescription) }
  }
}
