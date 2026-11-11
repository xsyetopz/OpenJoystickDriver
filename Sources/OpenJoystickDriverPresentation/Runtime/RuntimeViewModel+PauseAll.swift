import Foundation
import OpenJoystickDriverKit

extension RuntimeViewModel {
  /// Suspends every active controller; when none is active, resumes every suspended one.
  ///
  /// It does nothing while the status is not loaded.
  func togglePauseAll() async {
    guard case .available(let status) = statusState else { return }
    let active = status.devices.filter { $0.sessionState == .active }
    if active.isEmpty {
      for device in status.devices { await resumeController(device) }
    } else {
      for device in active { await suspendController(device) }
    }
  }
}
