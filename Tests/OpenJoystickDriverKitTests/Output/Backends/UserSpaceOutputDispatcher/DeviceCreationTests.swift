import CoreHID
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
      kIOHIDLocationIDKey as String: 3, kIOHIDMaxInputReportSizeKey as String: 15
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

  @Test(
    arguments: [
      (VirtualDeviceProfile.xboxSeries, kIOHIDTransportBluetoothValue),
      (VirtualDeviceProfile.xboxOneS, kIOHIDTransportBluetoothValue),
      (VirtualDeviceProfile.xbox360Wired, kIOHIDTransportUSBValue),
      (VirtualDeviceProfile.dualShock4USB, kIOHIDTransportUSBValue),
      (VirtualDeviceProfile.dualSenseUSB, kIOHIDTransportUSBValue),
      (VirtualDeviceProfile.switchProUSB, kIOHIDTransportUSBValue),
      (VirtualDeviceProfile.openJoystickDriver, kIOHIDTransportUSBValue)
    ]
  )
  func ioHIDTransportValueMatchesIdentity(
    _ profile: VirtualDeviceProfile,
    _ expected: String
  ) {
    #expect(UserSpaceOutputDispatcher.ioHIDTransportValue(for: profile) == expected)
    let extra = UserSpaceOutputDispatcher.virtualDeviceExtraProperties(profile: profile)
    #expect(extra[kIOHIDTransportKey as String] as? String == expected)
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: profile,
      format: OJDGenericGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 1, productID: 1)
    )
    #expect(properties[kIOHIDTransportKey as String] as? String == expected)
  }

  @available(macOS 15, *)
  @Test(arguments: [VirtualDeviceProfile.xboxSeries, VirtualDeviceProfile.xboxOneS])
  func coreHIDBluetoothProfilesPublishBluetoothTransport(_ profile: VirtualDeviceProfile) {
    let properties = UserSpaceOutputDispatcher.virtualDeviceProperties(
      profile: profile,
      format: OJDGenericGamepadFormat(),
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )
    #expect(properties.transport == HIDDeviceTransport.bluetooth)
    #expect(UserSpaceOutputDispatcher.hidDeviceTransport(for: profile) == .bluetooth)
    #expect(
      UserSpaceOutputDispatcher.ioHIDTransportValue(for: profile) == kIOHIDTransportBluetoothValue
    )
    let extra = UserSpaceOutputDispatcher.virtualDeviceExtraProperties(profile: profile)
    #expect(extra[kIOHIDTransportKey as String] as? String == kIOHIDTransportBluetoothValue)
  }

  @available(macOS 15, *) @Test func coreHIDUSBProfilePublishesUSBTransport() {
    let properties = UserSpaceOutputDispatcher.virtualDeviceProperties(
      profile: .xbox360Wired,
      format: Xbox360MacHIDReportFormat(),
      identifier: DeviceIdentifier(vendorID: 13623, productID: 4112)
    )
    #expect(properties.transport == HIDDeviceTransport.usb)
    #expect(UserSpaceOutputDispatcher.hidDeviceTransport(for: .xbox360Wired) == .usb)
    #expect(
      UserSpaceOutputDispatcher.ioHIDTransportValue(for: .xbox360Wired) == kIOHIDTransportUSBValue
    )
  }

}
