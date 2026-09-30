#if canImport(AppKit)

  import Foundation
  import OpenJoystickDriverKit

  @MainActor
  final class MenuBarViewModel {
    let runtime: RuntimeViewModel

    init(runtime: RuntimeViewModel) { self.runtime = runtime }

    var devices: [ApplicationServiceDeviceDescription] {
      guard case .available(let status) = runtime.statusState else { return [] }
      return status.devices
    }

    var needsPermissionAttention: Bool {
      guard case .available(let status) = runtime.statusState else { return false }
      let needsPostEventAccess =
        status.requiresPostEventAccess == true && status.postEventAccess != .granted
      return !status.permissions.isReady || needsPostEventAccess
    }

    var summaryTitle: String {
      let readiness: String
      let controllerSummary: String
      switch runtime.statusState {
      case .loading:
        readiness = OJDLocalized.string("status.starting", fallback: "Starting...")
        controllerSummary = RuntimePresentation.deviceCountLabel(0)
      case .available(let status):
        readiness = status.readinessLabel
        controllerSummary = status.deviceCountLabel
      case .unavailable, .error:
        readiness = OJDLocalized.string("common.needsAttention", fallback: "Needs attention")
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
          "status.noActiveProfile",
          fallback: "No active profile"
        )
      }
      return [readiness, controllerSummary, profileSummary].joined(separator: " · ")
    }

    var summarySemanticState: SemanticState {
      switch runtime.statusState {
      case .loading: return .loading
      case .available(let status): return status.readiness == .ready ? .healthy : .attention
      case .unavailable, .error: return .failure
      }
    }

    func refresh() async {
      await runtime.refreshSystemExtensionSetup()
      await runtime.refresh()
    }

    func refreshLiveStatus() async -> Bool { await runtime.refreshLiveStatus() }
  }

#endif
