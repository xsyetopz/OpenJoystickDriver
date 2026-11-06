import Combine
import Foundation
import OpenJoystickDriverKit

/// Writes the stick dead zone changes of the detail's setting row, one at a time.
///
/// A change is computed from the record the row shows, so the editor stays busy until the service
/// wrote the record and the row read it again; a change made meanwhile is dropped, not computed
/// from the value the write replaces.
@MainActor
final class StickDeadzoneEditor: ObservableObject {
  /// Whether a change is waiting for the service or for the record to be read again.
  @Published
  private(set) var isWriting = false

  /// Sets the stick dead zone of the model of `device` to `value`, or removes it when `value` is
  /// nil, then calls `reload` if the service wrote the record.
  ///
  /// Does nothing while a change is in flight.
  ///
  /// - Parameters:
  ///   - value: The dead zone, or nil to remove the user's value.
  ///   - device: The controller.
  ///   - viewModel: The model of the app's view of the service, which sends the change.
  ///   - reload: Reads the record again.
  func change(
    to value: Double?,
    for device: ApplicationServiceDeviceDescription,
    viewModel: RuntimeViewModel,
    reload: () async -> Void
  ) async {
    guard !isWriting else { return }
    isWriting = true
    defer { isWriting = false }
    if await viewModel.setStickDeadzone(value, for: device) { await reload() }
  }
}
