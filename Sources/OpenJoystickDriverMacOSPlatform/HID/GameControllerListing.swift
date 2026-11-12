import Foundation
import GameController

/// Whether GameController lists a controller for a HID pad (D16).
enum GameControllerListing: Equatable, Sendable {
  /// The settle time since the device arrived has not passed.
  case settling
  /// GameController lists a controller for the device.
  case listed
  /// GameController lists no controller for the device after the settle time.
  case unlisted

  /// GameController lists OJD's virtual gamepad 16 to 18 ms after its HID device arrives
  /// (`openspec/changes/0-6-0-alpha-3/evidence/system-serving/`); no physical pad that macOS lists
  /// was measured, so the wait is about 50 times that.
  static let settleTime: DispatchTimeInterval = .seconds(1)

  /// GameController names no HID device, and a listed controller's `vendorName` is the HID
  /// `Product` string, so the product name is the tie.
  init(productName: String?, vendorNames: [String]) {
    self = productName.map(vendorNames.contains) == true ? .listed : .unlisted
  }

  /// The listing GameController holds now for a device with this product name.
  @MainActor
  static func current(productName: String?) -> Self {
    Self(productName: productName, vendorNames: GCController.controllers().compactMap(\.vendorName))
  }
}
