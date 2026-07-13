import Foundation
import IOKit
import IOKit.hid

struct UserSpaceDeviceCreationAttempt {
  let label: String
  let properties: [String: Any]
  let options: IOOptionBits
}

struct UserSpaceDeviceCreationRetryPolicy {
  static let defaultDelayNanoseconds: UInt64 = 5_000_000_000

  let delayNanoseconds: UInt64
  private(set) var nextAttemptNanoseconds: UInt64 = 0

  init(delayNanoseconds: UInt64 = Self.defaultDelayNanoseconds) {
    self.delayNanoseconds = delayNanoseconds
  }

  func permitsAttempt(at now: UInt64) -> Bool {
    now >= nextAttemptNanoseconds
  }

  mutating func recordFailure(at now: UInt64) {
    let (nextAttempt, overflow) = now.addingReportingOverflow(delayNanoseconds)
    nextAttemptNanoseconds = overflow ? UInt64.max : nextAttempt
  }
}

extension UserSpaceOutputDispatcher {
  static func deviceCreationAttempts(
    baseProperties: [String: Any],
    primaryUsage: Int
  ) -> [UserSpaceDeviceCreationAttempt] {
    let usageProperties: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: Int(kHIDPage_GenericDesktop),
      kIOHIDPrimaryUsageKey as String: primaryUsage,
      kIOHIDDeviceUsagePairsKey as String: [
        [
          kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
          kIOHIDDeviceUsageKey as String: primaryUsage,
        ],
      ],
    ]
    let noPairsUsageProperties: [String: Any] = [
      kIOHIDPrimaryUsagePageKey as String: Int(kHIDPage_GenericDesktop),
      kIOHIDPrimaryUsageKey as String: primaryUsage,
    ]
    let identityKeys = [
      kIOHIDReportDescriptorKey as String,
      kIOHIDVendorIDKey as String,
      kIOHIDProductIDKey as String,
      kIOHIDVersionNumberKey as String,
      kIOHIDProductKey as String,
      kIOHIDManufacturerKey as String,
      kIOHIDSerialNumberKey as String,
      kIOHIDTransportKey as String,
    ]
    let identityProperties = baseProperties.filter { identityKeys.contains($0.key) }
    let descriptorProperties = baseProperties.filter {
      $0.key == kIOHIDReportDescriptorKey as String
    }
    let createOnActivate = IOOptionBits(1 << 0)
    let defaultOptions = IOOptionBits(kIOHIDOptionsTypeNone)

    return [
      UserSpaceDeviceCreationAttempt(
        label: "full-usage-pairs/create-on-activate",
        properties: baseProperties.merging(usageProperties) { current, _ in current },
        options: createOnActivate
      ),
      UserSpaceDeviceCreationAttempt(
        label: "full-usage/create-on-activate",
        properties: baseProperties.merging(noPairsUsageProperties) { current, _ in current },
        options: createOnActivate
      ),
      UserSpaceDeviceCreationAttempt(
        label: "full/create-on-activate",
        properties: baseProperties,
        options: createOnActivate
      ),
      UserSpaceDeviceCreationAttempt(
        label: "identity-usage/create-on-activate",
        properties: identityProperties.merging(noPairsUsageProperties) { current, _ in current },
        options: createOnActivate
      ),
      UserSpaceDeviceCreationAttempt(
        label: "identity/default",
        properties: identityProperties,
        options: defaultOptions
      ),
      UserSpaceDeviceCreationAttempt(
        label: "descriptor/default",
        properties: descriptorProperties,
        options: defaultOptions
      ),
    ]
  }
}
