import Foundation
import OpenJoystickDriverKit

/// How a value field shows a value.
///
/// A field that applies to the controller but has no value (unknown, missing or not applicable)
/// shows the localized word "None", which VoiceOver reads as written. A field that can never apply
/// to the controller is hidden by its screen instead.
enum OJDValue: Equatable, Sendable {
  /// A value that is present.
  case text(String)
  /// No value; the field shows the word "None".
  case none

  /// The value, or ``none`` when it is nil or empty.
  init(_ value: String?) {
    if let value, !value.isEmpty { self = .text(value) } else { self = .none }
  }

  /// The value, or nil when it is missing.
  var textOrNil: String? {
    if case .text(let value) = self { return value }
    return nil
  }

  /// The text a value field shows.
  var displayText: String {
    switch self {
    case .text(let value): return value
    case .none: return OJDLocalized.string("status.none")
    }
  }

  /// The localization key that VoiceOver reads for a missing value, or nil for a present value.
  var accessibilityKey: String? {
    switch self {
    case .text: return nil
    case .none: return "status.none"
    }
  }
}

extension OJDValue {
  /// A reported string without surrounding whitespace; ``none`` when nothing is left.
  static func reported(_ value: String?) -> OJDValue {
    OJDValue(value?.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// A USB endpoint address; 0 means the controller reports none.
  static func endpoint(_ address: UInt8) -> OJDValue {
    address == 0 ? .none : .text(unsafe String(format: "0x%02X", address))
  }

  /// A USB vendor and product pair; both 0 means the controller reports none.
  static func usbIdentifier(vendorID: UInt16, productID: UInt16) -> OJDValue {
    vendorID == 0 && productID == 0
      ? .none : .text(unsafe String(format: "%04X:%04X", vendorID, productID))
  }

  /// The value for a sentence that VoiceOver or a sentence template reads: the spoken
  /// word for a missing value.
  var spokenText: String {
    switch self {
    case .text(let value): return value
    case .none: return OJDLocalized.string("status.none")
    }
  }
}

#if canImport(SwiftUI)

  import SwiftUI

  /// A value field's text through ``OJDValue``.
  struct OJDValueText: View {
    /// The value to show.
    let value: OJDValue

    /// Creates the text from a string, which is missing when it is nil or empty.
    init(_ value: String?) { self.value = OJDValue(value) }

    /// Creates the text from a value.
    init(value: OJDValue) { self.value = value }

    /// The text of the value, with an accessibility value when the value has one.
    var body: some View {
      if let key = value.accessibilityKey {
        Text(value.displayText).ojdAccessibilityValue(OJDLocalized.string(key))
      } else {
        Text(value.displayText)
      }
    }
  }

#endif
