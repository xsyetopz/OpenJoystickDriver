#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  /// Reads the runtime state for the status item and the main menu.
  @MainActor
  final class MenuBarViewModel {
    /// The runtime state that the menu bar item reads.
    let runtime: RuntimeViewModel

    /// Creates the view model on `runtime`.
    init(runtime: RuntimeViewModel) {
      self.runtime = runtime
    }

    /// The connected controllers, or none while the service status is not available.
    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    /// The problems that need the user's action: the service when its state is a problem, then each
    /// permission the Access area shows as missing.
    var problems: [StatusItemProblem] {
      var found: [StatusItemProblem] = []
      let readiness = ServiceReadiness.resolve(
        ServiceReadinessInput(
          status: runtime.statusState,
          listenerStopped: runtime.listenerFailure != nil,
          registration: ServiceReadiness.currentRegistration(for: runtime.statusState)
        )
      )
      if readiness.isProblem { found.append(.service(readiness)) }
      found += AccessReadiness.missingPermissions(
        permissionState: runtime.permissionState,
        statusState: runtime.statusState
      ).map(StatusItemProblem.missingPermission)
      return found
    }

    /// The data that the status menu is built from.
    var statusItemState: StatusItemState {
      var snapshot: ApplicationServiceRemappingSnapshotPayload?
      if case .available(let available) = runtime.remappingState {
        snapshot = available
      }
      return StatusItemState(
        problems: problems,
        controllers: devices.map {
          var controller = StatusItemState.Controller(
            id: $0.sessionToken.rawValue,
            name: $0.name,
            isSuspended: $0.sessionState == .suspended,
            isWireless: $0.supportsWirelessDisconnect,
            profiles: Self.profiles(applyingTo: $0, in: snapshot)
          )
          controller.battery = $0.connectionState?.power.battery.percentageText
          controller.profileInForce = Self.profileInForceText(
            $0.profileInForce,
            appName: ProfileAppChoices.appName
          )
          return controller
        },
        profileListRead: snapshot != nil
      )
    }

    /// The profile name for a controller row, followed by the app that selected the profile.
    static func profileInForceText(
      _ profile: ApplicationServiceProfileInForce?,
      appName: (String) -> String
    ) -> String? {
      guard let profile else { return nil }
      return profile.appID.map {
        OJDLocalized.formatted("ui.menu.controller.profileForApp", profile.name, appName($0))
      } ?? profile.name
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

    /// Reads the driver extension setup and the service status again.
    func refresh() async {
      runtime.refreshSystemExtensionSetup()
      await runtime.refresh()
    }

    /// Reads the live service status again and returns whether it changed.
    func refreshLiveStatus() async -> Bool { await runtime.refreshLiveStatus() }
  }

#endif
