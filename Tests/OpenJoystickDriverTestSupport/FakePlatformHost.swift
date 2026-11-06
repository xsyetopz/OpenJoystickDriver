import Foundation

@testable import OpenJoystickDriverKit

// The protocol requires `async`; the fake answers immediately.
// swiftlint:disable async_without_await

/// A `PlatformHost` that reports an absent extension and no USB controllers, so tests never touch
/// real USB or `systemextensionsctl`.
package struct FakePlatformHost: PlatformHost {
  package init() {}

  package var extensionID: String { "com.openjoystickdriver.fake-extension" }

  package func extensionStatus(bundleURL: URL) -> ExtensionStatus {
    ExtensionStatus(bundle: .missing, registration: .absent)
  }

  package func requestExtensionActivation() async -> SystemExtensionSetupRequestResult { .failed }

  package func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult {
    .failed
  }

  package func countVendorSpecificUSBControllers() async throws -> Int { 0 }

  package func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool { false }

  package var accessControl: any AccessControlSystem { FixedAccessControlSystem() }

  package var mainAppRegistration: any ApplicationServiceRegistration {
    FakeMainAppRegistration()
  }

  package func codeSigningIdentity(ofPath url: URL) -> CodeSigningIdentity? { nil }

  package func physicalReportDescriptor(vendorID: Int, productID: Int) -> [UInt8]? { nil }

  package func physicalDevice(vendorID: Int, productID: Int) -> PhysicalDevice? { nil }

  package func droppedHIDInputReports(processID: Int32) -> [HIDInputDropObservation] { [] }

  @MainActor
  package func runApplication() -> Never { fatalError("Tests never run the application.") }
}

// swiftlint:enable async_without_await
