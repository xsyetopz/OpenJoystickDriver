package import Foundation

@testable package import OpenJoystickDriverKit

// The protocol requires `async`; the fake answers immediately.
// swiftlint:disable async_without_await

/// A `PlatformHost` that reports an absent extension and no USB controllers, so tests never touch
/// real USB or `systemextensionsctl`.
package struct FakePlatformHost: PlatformHost {
  /// The controllers the fake extension's entitlement covers.
  private let covered: Set<ControllerModelID>

  package init(entitlementCovers covered: Set<ControllerModelID> = []) {
    self.covered = covered
  }

  package var extensionID: String { "com.openjoystickdriver.fake-extension" }

  package func extensionStatus(bundleURL _: URL) -> ExtensionStatus {
    ExtensionStatus(bundle: .missing, registration: .absent)
  }

  package func requestExtensionActivation() async -> SystemExtensionSetupRequestResult {
    .failed(Self.failure)
  }

  package func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult {
    .failed(Self.failure)
  }

  private static let failure = SystemExtensionRequestFailure(
    domain: "FakePlatformHost",
    code: 1,
    text: "The fake host does not submit requests."
  )

  package func countVendorSpecificUSBControllers() async -> Int { 0 }

  package func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool {
    covered.contains(ControllerModelID(vendorID: vendorID, productID: productID))
  }

  package var accessControl: any AccessControlSystem { FixedAccessControlSystem() }

  package var mainAppRegistration: any ApplicationServiceRegistration {
    FakeMainAppRegistration()
  }

  package func codeSigningIdentity(ofPath _: URL) -> CodeSigningIdentity? { nil }

  package func physicalReportDescriptor(vendorID _: Int, productID _: Int) -> [UInt8]? { nil }

  package func physicalDevice(vendorID _: Int, productID _: Int) -> PhysicalDevice? { nil }

  package func droppedHIDInputReports(processID _: Int32) -> [HIDInputDropObservation] { [] }

  @MainActor
  package func runApplication() -> Never { fatalError("Tests never run the application.") }
}

// swiftlint:enable async_without_await
