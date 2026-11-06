#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  /// Reads the runtime state for the status item and the main menu.
  @MainActor
  final class MenuBarViewModel {
    /// The runtime state that the menu bar item reads.
    let runtime: RuntimeViewModel
    /// Formats the status line.
    private let localization: Localization

    /// Creates the view model on `runtime`.
    init(runtime: RuntimeViewModel, localization: Localization = Localization()) {
      self.runtime = runtime
      self.localization = localization
    }

    /// The connected controllers, or none while the service status is not available.
    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    /// Whether the Access area has a permission to grant; see
    /// ``AccessReadiness/hasMissingPermission(permissionState:statusState:)``.
    var needsPermissionAttention: Bool {
      AccessReadiness.hasMissingPermission(
        permissionState: runtime.permissionState,
        statusState: runtime.statusState
      )
    }

    /// The status line: readiness, controller count and active profile.
    ///
    /// The active profile is the global one when there is one, else the last active profile.
    var summaryTitle: String {
      let readiness: String
      let controllerSummary: String
      switch runtime.statusState {
      case .loading:
        readiness = OJDLocalized.string("status.starting")
        controllerSummary = RuntimePresentation.deviceCountLabel(0)
      case .available(let status):
        readiness = status.readinessLabel
        controllerSummary = status.deviceCountLabel
      case .unavailable, .error:
        readiness = OJDLocalized.string("status.needsAttention")
        controllerSummary = RuntimePresentation.deviceCountLabel(0)
      }

      let profileSummary: String
      if case .available(let snapshot) = runtime.remappingState,
        let activeProfile = snapshot.activeProfiles.last(where: { $0.applicationScope == .global })
          ?? snapshot.activeProfiles.last,
        let profile = snapshot.profiles.first(where: { $0.id == activeProfile.profileID })
      {
        profileSummary = profile.name
      } else {
        profileSummary = OJDLocalized.string(
          "status.noActiveProfile"
        )
      }
      return StatusItemStatusLine.make(
        readiness: readiness,
        controllers: controllerSummary,
        profile: profileSummary,
        localization: localization,
        locale: .current
      )
    }

    /// The data that the status menu is built from.
    var statusItemState: StatusItemState {
      var profiles: [StatusItemState.Profile] = []
      var snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let available) = runtime.remappingState {
        snapshot = available
      }
      if let snapshot {
        let activeIDs = Set(snapshot.activeProfiles.map(\.profileID))
        profiles = snapshot.profiles.map {
          StatusItemState.Profile(id: $0.id, name: $0.name, isActive: activeIDs.contains($0.id))
        }
      }
      return StatusItemState(
        statusLine: summaryTitle,
        needsAccess: needsPermissionAttention,
        controllers: devices.map {
          StatusItemState.Controller(
            id: $0.sessionToken.rawValue,
            name: $0.name,
            isSuspended: $0.sessionState == .suspended,
            isWireless: $0.supportsWirelessDisconnect,
            profiles: Self.profiles(applyingTo: $0, in: snapshot)
          )
        },
        profiles: profiles,
        profileListRead: snapshot != nil,
        statusSymbolName: summarySemanticState.presentation.symbolName
      )
    }

    /// The profiles of the snapshot that apply to the controller: its model, and its unit when the
    /// profile names one.
    ///
    /// The active one is the profile routing uses for the controller's model.
    static func profiles(
      applyingTo device: ApplicationServiceDeviceDescription,
      in snapshot: ApplicationServiceRemappingSnapshotPayload?
    ) -> [StatusItemState.Profile] {
      guard let snapshot else { return [] }
      let activeID = snapshot.activeProfiles.routingActiveProfile(
        vendorID: device.vendorID,
        productID: device.productID
      )?.profileID
      return snapshot.profiles.filter {
        $0.device.vendorID == device.vendorID && $0.device.productID == device.productID
          && ($0.device.unit == nil || $0.device.unit == device.portKey?.rawValue)
      }.map { StatusItemState.Profile(id: $0.id, name: $0.name, isActive: $0.id == activeID) }
    }

    /// The state whose symbol sits beside the status line.
    var summarySemanticState: SemanticState {
      switch runtime.statusState {
      case .loading: return .loading
      case .available(let status): return status.readiness == .ready ? .healthy : .attention
      case .unavailable, .error: return .failure
      }
    }

    /// Reads the driver extension setup and the service status again.
    func refresh() async {
      await runtime.refreshSystemExtensionSetup()
      await runtime.refresh()
    }

    /// Reads the live service status again and returns whether it changed.
    func refreshLiveStatus() async -> Bool { await runtime.refreshLiveStatus() }
  }

#endif
