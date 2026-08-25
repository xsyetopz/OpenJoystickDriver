#if canImport(AppKit)

  import Foundation
  import ServiceManagement

  protocol LaunchAtLoginControlling {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
  }

  struct SystemLaunchAtLoginController: LaunchAtLoginControlling {
    var isAvailable: Bool {
      if #available(macOS 13.0, *) { return true }
      return false
    }

    var isEnabled: Bool {
      if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
      return false
    }

    func setEnabled(_ enabled: Bool) throws {
      guard #available(macOS 13.0, *) else { return }
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    }
  }

#endif
