package import CryptoKit
package import Foundation

@testable package import OpenJoystickDriverKit

/// An ``AccessControlSystem`` that reports the states it was given and ignores access requests.
package struct FixedAccessControlSystem: AccessControlSystem {
  package var inputRead: PermissionManager.AccessState
  package var inputInject: PermissionManager.AccessState
  package var postEvent: RemappingPostEventAccessState

  package init(
    inputRead: PermissionManager.AccessState = .granted,
    inputInject: PermissionManager.AccessState = .granted,
    postEvent: RemappingPostEventAccessState = .granted
  ) {
    self.inputRead = inputRead
    self.inputInject = inputInject
    self.postEvent = postEvent
  }

  package func inputReadAccessState() -> PermissionManager.AccessState { inputRead }
  package func inputInjectAccessState() -> PermissionManager.AccessState { inputInject }
  package func postEventAccessState() -> RemappingPostEventAccessState { postEvent }

  @MainActor
  package func requestInputReadAccess() {}

  @MainActor
  package func requestInputInjectAccess() {}
}

/// A login-item registration that is never registered and accepts every change.
package struct FakeMainAppRegistration: ApplicationServiceRegistration {
  package init() {}

  package var status: ApplicationServiceRegistrationStatus { .notRegistered }

  package func register() {}

  package func unregister() {}
}

/// The transport an IOHID `Transport` property value stands for, or nil for an unknown value.
package func testHostTransport(_ property: String?) -> PhysicalTransport? {
  switch property {
  case "USB": .usb
  case "Bluetooth": .bluetoothClassic
  case "BluetoothLowEnergy": .bluetoothLE
  default: nil
  }
}

extension PermissionManager {
  /// A manager over a ``FixedAccessControlSystem`` that grants everything.
  package static func grantingAll() -> PermissionManager {
    PermissionManager(system: FixedAccessControlSystem())
  }
}

// The protocol requires `async`; the fake answers immediately.
// swiftlint:disable async_without_await

/// A ``HIDAccessBackend`` with no devices, for managers whose tests drive USB or injected events.
package struct NoDevicesHIDAccessBackend: HIDAccessBackend {
  package init() {}

  package func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    AsyncStream { _ in }
  }

  package func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? { [] }

  package func setOutputReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> { .unavailable }

  package func setOutputReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> { .unavailable }

  package func setFeatureReport(
    address _: ControllerConnectionAddress,
    report _: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> { .unavailable }

  package func setFeatureReport(
    connection _: HIDDeviceConnection,
    report _: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> { .unavailable }

  package func getFeatureReport(
    address _: ControllerConnectionAddress,
    request _: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> { .unavailable }

  package func getFeatureReport(
    connection _: HIDDeviceConnection,
    request _: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> { .unavailable }

  package func releaseInputClaim(
    address _: ControllerConnectionAddress
  ) async
    -> PhysicalHIDClaimResult
  { .unavailable }

  package func reacquireInputClaim(
    address _: ControllerConnectionAddress
  ) async
    -> PhysicalHIDClaimResult
  { .unavailable }

  package func retryInputClaim(address _: ControllerConnectionAddress) async {}

  package func routeElementValues(connection _: HIDDeviceConnection) async {}
}

// swiftlint:enable async_without_await

extension DeviceManager {
  /// A manager over no HID devices that grants every permission.
  package init(
    dispatcher: any OutputDispatcher,
    installationKey: SymmetricKey,
    usbTransportProvider: (any USBTransportProvider)? = nil,
    wirelessControllerDisconnector: (any WirelessControllerDisconnecting)? = nil
  ) {
    self.init(
      dispatcher: dispatcher,
      installationKey: installationKey,
      usbTransportProvider: usbTransportProvider,
      wirelessControllerDisconnector: wirelessControllerDisconnector,
      hidManager: HIDManager(backend: NoDevicesHIDAccessBackend()),
      permissionManager: .grantingAll()
    )
  }

  /// A manager over `hidManager` that grants every permission.
  package init(
    dispatcher: any OutputDispatcher,
    installationKey: SymmetricKey,
    hidManager: HIDManager,
    usbTransportProvider: (any USBTransportProvider)? = nil
  ) {
    self.init(
      dispatcher: dispatcher,
      installationKey: installationKey,
      usbTransportProvider: usbTransportProvider,
      wirelessControllerDisconnector: nil,
      hidManager: hidManager,
      permissionManager: .grantingAll()
    )
  }
}
