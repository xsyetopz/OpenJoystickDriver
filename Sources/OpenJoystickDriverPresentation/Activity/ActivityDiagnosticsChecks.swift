import Foundation
import OpenJoystickDriverKit

/// Gathers the facts for the checks of `ojd diagnose` and runs them through the same
/// `DiagnosticsService` that the command uses.
enum ActivityDiagnosticsChecks {
  /// Returns the results of the checks of `ojd diagnose` that the app lists, after asking the
  /// service through `gateway`.
  static func run(gateway: any ApplicationServiceGateway) async -> [DiagnoseCheck] {
    let snapshot = await serviceSnapshot(gateway)
    let bundleURL = Bundle.main.bundleURL
    // `systemextensionsctl` blocks, so it runs off the main actor.
    let extensionStatus = await Task.detached {
      PlatformHosts.current.extensionStatus(bundleURL: bundleURL)
    }.value
    let usb: Result<Int, any Error>
    do { usb = .success(try await PlatformHosts.current.countVendorSpecificUSBControllers()) } catch
    { usb = .failure(error) }
    return DiagnosticsService.checks(
      snapshot: snapshot,
      extensionStatus: extensionStatus,
      records: ControllerRecordSet.load(userDirectory: ControllerRecordSet.userDirectory),
      virtualDevices: VirtualHIDProfileOverrideStore(
        directory: VirtualHIDProfileOverrideStore.userDirectory
      ).files,
      usb: usb
    )
  }

  /// Asks the service once, as `ojd diagnose` does; a stopped or failing service never throws.
  static func serviceSnapshot(
    _ gateway: any ApplicationServiceGateway
  ) async
    -> DiagnoseServiceSnapshot
  {
    await DiagnoseServiceSnapshot.gather(
      status: { try await gateway.status() },
      virtualDiagnostics: { try await gateway.virtualDeviceDiagnostics() },
      frameTimings: { try await gateway.frameTimings(lastSeconds: nil) },
      listenerFailure: ServiceListenerFailure.readDefault
    )
  }
}
