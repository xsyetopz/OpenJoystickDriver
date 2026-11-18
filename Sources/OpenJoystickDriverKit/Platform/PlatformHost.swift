package import Foundation

/// The operating-system services the neutral command grammar reaches for.
///
/// A host adapter module conforms to it and the executable installs the conformance before any
/// command runs.
package protocol PlatformHost: Sendable {
  /// The bundle identifier of the DriverKit extension the host installs.
  var extensionID: String { get }

  /// Reads the extension's installed and registered state for the app at `bundleURL`.
  func extensionStatus(bundleURL: URL) -> ExtensionStatus

  /// Submits an activation request for the extension and returns the system's answer.
  func requestExtensionActivation() async -> SystemExtensionSetupRequestResult

  /// Submits a deactivation request for the extension and returns the system's answer.
  func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult

  /// Counts the vendor-specific USB controllers the host can see.
  func countVendorSpecificUSBControllers() async throws -> Int

  /// Whether the signed extension's USB entitlement lists this controller.
  func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool

  /// The host's answer to, and request flow for, the access the driver needs.
  var accessControl: any AccessControlSystem { get }

  /// The main application's login-item registration.
  var mainAppRegistration: any ApplicationServiceRegistration { get }

  /// The signing identity of the code at `url`; nil when the path holds no signed code.
  func codeSigningIdentity(ofPath url: URL) -> CodeSigningIdentity?

  /// The HID report descriptor of a connected controller model, or nil when none is connected.
  func physicalReportDescriptor(vendorID: Int, productID: Int) -> [UInt8]?

  /// The identity and HID elements of a connected controller model, read locally from the device
  /// that ``physicalReportDescriptor(vendorID:productID:)`` reads; nil when none is connected.
  func physicalDevice(vendorID: Int, productID: Int) -> PhysicalDevice?

  /// The input reports the system dropped for each HID device that process `processID` reads.
  func droppedHIDInputReports(processID: Int32) -> [HIDInputDropObservation]

  /// Runs the application until it exits; the executable calls it when not run as the tool.
  @MainActor
  func runApplication() -> Never
}

/// Holds the installed `PlatformHost`.
package enum PlatformHosts {
  /// The installed host; nil until `install` runs.
  private static let installed = Locked<(any PlatformHost)?>(nil)

  /// Installs `host`; the executable calls it once at launch, and tests call it to inject a fake.
  package static func install(_ host: any PlatformHost) {
    installed.withLock { $0 = host }
  }

  /// The installed host.
  ///
  /// Reading it before `install` is a programming error.
  package static var current: any PlatformHost {
    guard let host = installed.withLock({ $0 }) else {
      preconditionFailure("No PlatformHost installed; the executable installs one at launch.")
    }
    return host
  }
}

/// The ports the access WebSocket may listen on.
package enum AccessWebPorts {
  /// The ports the WebSocket may listen on.
  package static let allowed = 1_024...65_535
}
