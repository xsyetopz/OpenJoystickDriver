#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  /// The state of the Controllers list: the selected controller, and the lists derived from the
  /// runtime's status.
  @MainActor
  final class ControllersViewModel: ObservableObject {
    /// The session token of the selected controller, or nil before a selection.
    @Published
    private(set) var selectedSessionToken: String?
    /// The ID of the selected device that OJD does not serve, or nil; it replaces the selected
    /// controller.
    @Published
    private(set) var selectedUnservedID: String?

    /// The model of the app's view of the service.
    let runtime: RuntimeViewModel
    /// Redraws the screen when the runtime's status changes.
    private var runtimeObservation: AnyCancellable?

    /// Creates the model on `runtime`.
    ///
    /// - Parameter runtime: The model of the app's view of the service.
    init(runtime: RuntimeViewModel) {
      self.runtime = runtime
      // The list is derived from the runtime's status, so its changes must redraw this screen.
      runtimeObservation = runtime.$statusState.map { _ in () }.merge(
        with: runtime.$liveStatusError.map { _ in () }
      ).sink { [weak self] in self?.objectWillChange.send() }
    }

    /// The message of the failed live status, or nil.
    var liveStatusError: String? { runtime.liveStatusError }

    /// The connected controllers, or none while the status is not loaded.
    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    /// Connected devices OJD does not serve, each with the reason and how to free it.
    var unservedDevices: [RuntimeUnservedDevice] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.unservedDevices
    }

    /// Whether the controller inventory is refreshing.
    var isRefreshing: Bool { runtime.isScopedRefreshInFlight }

    /// The selected device that OJD does not serve, or nil when none is selected or it left.
    var selectedUnserved: RuntimeUnservedDevice? {
      unservedDevices.first { $0.id == selectedUnservedID }
    }

    /// The selected controller, or the first one when none is selected or the selection left.
    ///
    /// Nil while a device that OJD does not serve is selected.
    var selectedDevice: ApplicationServiceDeviceDescription? {
      if selectedUnserved != nil { return nil }
      guard let selectedSessionToken else { return devices.first }
      return devices.first { $0.sessionToken.rawValue == selectedSessionToken } ?? devices.first
    }

    /// Selects the first controller when the selection is not connected.
    func synchronizeSelection() {
      if selectedUnserved != nil { return }
      guard let selectedSessionToken,
        devices.contains(where: { $0.sessionToken.rawValue == selectedSessionToken })
      else {
        self.selectedSessionToken = devices.first?.sessionToken.rawValue
        return
      }
    }

    /// Selects the controller.
    ///
    /// - Parameter device: The controller to select.
    func select(_ device: ApplicationServiceDeviceDescription) {
      selectedUnservedID = nil
      selectedSessionToken = device.sessionToken.rawValue
    }

    /// Selects the device that OJD does not serve.
    ///
    /// - Parameter device: The device to select.
    func select(unserved device: RuntimeUnservedDevice) {
      selectedUnservedID = device.id
    }

    /// Selects the controller with this session token, for "Show in Window".
    ///
    /// - Parameter sessionToken: The session token.
    /// - Returns: False when no connected controller has it; the selection stays as it is.
    @discardableResult
    func select(sessionToken: String) -> Bool {
      guard devices.contains(where: { $0.sessionToken.rawValue == sessionToken }) else {
        return false
      }
      selectedSessionToken = sessionToken
      return true
    }

    /// Refreshes the controller inventory.
    func refresh() { Task { await runtime.refreshControllerInventory() } }

    /// Returns the profile that is active for the controller, or why none shows.
    ///
    /// - Parameter device: The controller.
    /// - Returns: The profile that is active for the controller, or why none shows.
    func activeProfileState(
      for device: ApplicationServiceDeviceDescription
    ) -> RuntimeActiveProfileState {
      switch runtime.remappingState {
      case .loading: return .loading
      case .unavailable(let message): return .unavailable(message)
      case .error(let message): return .error(message)
      case .available(let snapshot):
        guard
          let profile = snapshot.activeProfiles.routingActiveProfile(
            vendorID: device.vendorID,
            productID: device.productID
          )
        else { return .noProfile }
        return .profile(profile.profileName)
      }
    }
  }

#endif
