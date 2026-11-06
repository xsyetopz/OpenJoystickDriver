import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverMacOSPlatform
import OpenJoystickDriverService
import OpenJoystickDriverUSB

/// The macOS host adapter: the system-extension, USB, and application services the neutral command
/// grammar reaches through `PlatformHost`.
package struct MacOSPlatformHost: PlatformHost {
  /// Creates the host.
  package init() {}

  /// The bundle identifier of the DriverKit transport extension.
  package var extensionID: String { ExtensionProbe.extensionID }

  /// Reads the state of the transport extension in the app bundle at `bundleURL`.
  package func extensionStatus(bundleURL: URL) -> ExtensionStatus {
    ExtensionProbe.currentStatus(bundleURL: bundleURL)
  }

  /// Asks macOS to activate the transport extension.
  package func requestExtensionActivation() async -> SystemExtensionSetupRequestResult {
    await DefaultSystemExtensionSetupClient().requestActivation()
  }

  /// Asks macOS to deactivate the transport extension.
  package func requestExtensionDeactivation() async -> SystemExtensionSetupRequestResult {
    await DefaultSystemExtensionSetupClient().requestDeactivation()
  }

  /// Counts the vendor-specific USB controllers that the raw USB transport provider finds.
  package func countVendorSpecificUSBControllers() async throws -> Int {
    try await USBControllerScanner.scanVendorSpecific(
      using: OpenJoystickDriverUSBTransportProvider()
    ).count
  }

  /// Tells whether the signed extension may claim the USB controller `vendorID` and `productID`.
  ///
  /// Its entitlement lists the Microsoft vendor ID and a set of product IDs that Apple signs.
  package func extensionEntitlementCovers(vendorID: UInt16, productID: UInt16) -> Bool {
    vendorID == USBDriverKitExtensionConfiguration.microsoftVendorID
      && USBDriverKitExtensionConfiguration.microsoftProductIDs.contains(productID)
  }

  /// The macOS permission checks and requests for the HID access that OJD needs.
  package var accessControl: any AccessControlSystem { MacOSAccessControlSystem() }

  /// The login-item registration of the main app.
  package var mainAppRegistration: any ApplicationServiceRegistration {
    MainAppServiceRegistration()
  }

  /// Reads the code signing identity of the program at `url`.
  package func codeSigningIdentity(ofPath url: URL) -> CodeSigningIdentity? {
    CodeSigningIdentity.of(path: url)
  }

  /// Copies the HID report descriptor of the connected device with `vendorID` and `productID`.
  package func physicalReportDescriptor(vendorID: Int, productID: Int) -> [UInt8]? {
    PhysicalReportDescriptor.copy(vendorID: vendorID, productID: productID)
  }

  /// Returns the dropped HID input report counts that the IORegistry holds for `processID`.
  package func droppedHIDInputReports(processID: Int32) -> [HIDInputDropObservation] {
    HIDInputReportDrops.observations(processID: processID)
  }

  /// Runs the app without a window until it exits.
  @MainActor
  package func runApplication() -> Never {
    let host = HeadlessApplicationHost()
    host.run()
  }
}
