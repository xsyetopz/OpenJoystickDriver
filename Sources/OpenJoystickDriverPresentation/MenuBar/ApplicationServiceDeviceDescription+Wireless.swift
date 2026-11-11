import OpenJoystickDriverKit

extension ApplicationServiceDeviceDescription {
  /// Whether the service can close the controller's wireless link, from the typed transport it
  /// reports.
  ///
  /// Only a classic Bluetooth link has a disconnect path: no supported API closes a
  /// system-connected Bluetooth LE link, and a controller that reports no transport has none.
  var supportsWirelessDisconnect: Bool { connectionState?.transport == .bluetoothClassic }
}
