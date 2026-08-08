import Foundation
import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceDeviceCreationTests {
  @Test func attemptsProgressFromFullDeferredCreationToDocumentedMinimum() throws {
    let descriptor = Data([0x05, 0x01, 0x09, 0x05])
    let base: [String: Any] = [
      kIOHIDReportDescriptorKey as String: descriptor, kIOHIDVendorIDKey as String: 1,
      kIOHIDProductIDKey as String: 2, kIOHIDProductKey as String: "Test",
      kIOHIDLocationIDKey as String: 3, kIOHIDMaxInputReportSizeKey as String: 15,
    ]

    let attempts = UserSpaceOutputDispatcher.deviceCreationAttempts(
      baseProperties: base,
      primaryUsage: Int(kHIDUsage_GD_GamePad)
    )

    #expect(attempts.first?.options == IOOptionBits(1 << 0))
    #expect(attempts.last?.options == IOOptionBits(kIOHIDOptionsTypeNone))
    #expect(attempts.last?.properties.count == 1)
    #expect(attempts.last?.properties[kIOHIDReportDescriptorKey as String] as? Data == descriptor)
    #expect(attempts.map(\.label).count == Set(attempts.map(\.label)).count)
  }
  @Test func retryPolicyPermitsOneAttemptPerDelayWindow() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    #expect(policy.permitsAttempt(at: 100))
    policy.recordFailure(at: 100)

    #expect(!policy.permitsAttempt(at: 100))
    #expect(!policy.permitsAttempt(at: 104))
    #expect(policy.permitsAttempt(at: 105))
  }

  @Test func retryPolicyClampsOverflowAtMaximumTimestamp() {
    var policy = UserSpaceDeviceCreationRetryPolicy(delayNanoseconds: 5)

    policy.recordFailure(at: UInt64.max - 2)

    #expect(policy.nextAttemptNanoseconds == UInt64.max)
    #expect(!policy.permitsAttempt(at: UInt64.max - 1))
    #expect(policy.permitsAttempt(at: UInt64.max))
  }

}
