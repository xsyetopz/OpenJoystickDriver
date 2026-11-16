import Dispatch
import Foundation
import OpenJoystickDriverKit

/// Prints the reports that the running service receives from the controller `vendorID:productID`
/// for `seconds`, and returns the process exit code; nil when the service does not serve that
/// controller, so the caller keeps its own error.
///
/// The service holds the device exclusively, so a second open fails; its packet log carries the
/// same reports.
func monitorThroughService(vendorID: UInt16, productID: UInt16, seconds: Int) -> Int32? {
  let result = Locked<Int32?>(nil)
  let done = DispatchSemaphore(value: 0)
  Task {
    defer { done.signal() }
    let client = ApplicationServiceClient()
    await client.connect(timeoutSeconds: 0)
    guard client.isConnected else { return }
    defer { client.disconnect() }
    guard
      let device = try? await client.getStatus().connectedDevices.first(where: {
        $0.vendorID == vendorID && $0.productID == productID
      })
    else { return }
    print("Monitoring through the service, session=\(device.sessionToken.rawValue), \(seconds)s")
    let reports = Locked(0)
    do {
      try await PacketLogStream.follow(
        duration: Double(seconds),
        read: { try await client.packetLog(for: .session(device.sessionToken)) },
        onEntry: { entry in
          reports.withLock { $0 += 1 }
          print("REPORT dir=\(entry.direction.rawValue) len=\(entry.length) bytes=\(entry.hex)")
          unsafe fflush(stdout)
        }
      )
    } catch {
      unsafe fputs("ERROR: service packet log failed: \(error)\n", unsafe stderr)
      result.withLock { $0 = 1 }
      return
    }
    let count = reports.withLock { $0 }
    print("SUMMARY values=0 reports=\(count)")
    result.withLock { $0 = count > 0 ? 0 : 3 }
  }
  done.wait()
  return result.withLock { $0 }
}
