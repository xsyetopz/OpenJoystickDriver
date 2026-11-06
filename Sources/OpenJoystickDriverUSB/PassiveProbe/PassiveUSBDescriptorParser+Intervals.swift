import Foundation

extension PassiveUSBConfigurationDescriptorParser {

  /// Returns the nominal interval in microseconds of an endpoint, or nil when the speed or the
  /// interval has none.
  static func nominalIntervalMicroseconds(
    transferType: UInt8,
    interval: UInt8,
    speed: PassiveUSBNegotiatedSpeed?
  ) -> UInt64? {
    guard let speed, interval >= 1 else { return nil }
    switch speed {
    case .low: return transferType == 3 ? UInt64(interval) * 1_000 : nil
    case .full:
      if transferType == 3 { return UInt64(interval) * 1_000 }
      if transferType == 1, interval <= 16 { return (UInt64(1) << UInt64(interval - 1)) * 1_000 }
      return nil
    case .high, .superSpeed, .superSpeedPlus:
      guard transferType == 1 || transferType == 3, interval <= 16 else { return nil }
      return (UInt64(1) << UInt64(interval - 1)) * 125
    }
  }

  /// Tells whether `interval` is valid for the transfer type and speed.
  static func intervalResult(
    transferType: UInt8,
    interval: UInt8,
    speed: PassiveUSBNegotiatedSpeed?
  ) -> PassiveUSBIntervalResult {
    guard let speed else { return .unsupportedSpeedOrTransfer }
    guard transferType == 1 || transferType == 3 else { return .ignoredNotServiceInterval }
    guard interval > 0 else { return .invalidRange }
    if transferType == 1, interval > 16 { return .invalidRange }
    switch speed {
    case .low:
      return transferType == 3
        ? .validDescriptorNominal(UInt64(interval) * 1_000) : .unsupportedSpeedOrTransfer
    case .full:
      if transferType == 3 { return .validDescriptorNominal(UInt64(interval) * 1_000) }
      return .validDescriptorNominal((UInt64(1) << UInt64(interval - 1)) * 1_000)
    case .high, .superSpeed, .superSpeedPlus:
      guard interval <= 16 else { return .invalidRange }
      return .validDescriptorNominal((UInt64(1) << UInt64(interval - 1)) * 125)
    }
  }
}
