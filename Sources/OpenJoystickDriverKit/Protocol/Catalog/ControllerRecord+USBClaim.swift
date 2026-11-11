extension ControllerRecord {
  /// Whether the signed USB extension can claim this raw-USB controller; nil for a family that does
  /// not use raw USB.
  ///
  /// The extension's USB entitlement is a product list Apple signs, so a user record cannot add a
  /// product to it.
  public var isClaimedByUSBExtension: Bool? {
    guard usesRawUSB else { return nil }
    return PlatformHosts.current.extensionEntitlementCovers(
      vendorID: model.vendorID,
      productID: model.productID
    )
  }
}

extension ControllerRecord {
  /// Why OJD cannot claim a raw-USB controller through the signed extension, in words; nil when
  /// it can or the family does not use raw USB.
  public var usbNote: String? {
    isClaimedByUSBExtension == false
      ? Localization().string("platform.macos.cli.record.group.usbNotClaimed") : nil
  }

  /// Why OJD reaches a Switch 2 record without `bluetoothLE` only over USB, in words.
  public var bluetoothLENote: String? {
    isSwitch2WithoutBluetoothLE ? Localization().string("cli.record.group.usbOnlySwitch2") : nil
  }

  /// Every note that explains a limit on how OJD reaches the controller.
  public var notes: [String] { [usbNote, bluetoothLENote].compactMap { $0 } }
}
