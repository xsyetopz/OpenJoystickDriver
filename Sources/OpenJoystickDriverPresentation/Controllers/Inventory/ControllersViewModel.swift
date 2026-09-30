#if canImport(SwiftUI)

  import Combine
  import Foundation
  import OpenJoystickDriverKit

  @MainActor
  final class ControllersViewModel: ObservableObject {
    @Published
    private(set) var selectedRuntimeIdentifier: String?

    let runtime: RuntimeViewModel
    private var runtimeObservation: AnyCancellable?

    init(runtime: RuntimeViewModel) {
      self.runtime = runtime
      // The list is derived from the runtime's status, so its changes must redraw this screen.
      runtimeObservation = runtime.$statusState.map { _ in () }.merge(
        with: runtime.$liveStatusError.map { _ in () }
      ).sink { [weak self] in self?.objectWillChange.send() }
    }

    var liveStatusError: String? { runtime.liveStatusError }

    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    var isRefreshing: Bool { runtime.isScopedRefreshInFlight }

    var selectedDevice: ApplicationServiceDeviceDescription? {
      guard let selectedRuntimeIdentifier else { return devices.first }
      return devices.first { $0.runtimeIdentifier == selectedRuntimeIdentifier } ?? devices.first
    }

    func synchronizeSelection() {
      guard let selectedRuntimeIdentifier,
        devices.contains(where: { $0.runtimeIdentifier == selectedRuntimeIdentifier })
      else {
        self.selectedRuntimeIdentifier = devices.first?.runtimeIdentifier
        return
      }
    }

    func select(_ device: ApplicationServiceDeviceDescription) {
      selectedRuntimeIdentifier = device.runtimeIdentifier
    }

    func refresh() { Task { await runtime.refreshControllerInventory() } }

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
