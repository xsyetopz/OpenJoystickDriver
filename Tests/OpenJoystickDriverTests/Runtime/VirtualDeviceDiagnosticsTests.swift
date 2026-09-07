import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct VirtualDeviceDiagnosticsTests {
  @Test func overlayCopiesGameControllerSupportFromMatchingOJDProbe() {
    let core = snapshot(vendorID: 0x054C, productID: 0x09CC, locationID: 1, supported: nil)
    let probe = snapshot(vendorID: 0x054C, productID: 0x09CC, locationID: 1, supported: true)
    let attached = HIDGameControllerSupport.attaching([core], from: [probe])
    #expect(attached.count == 1)
    #expect(attached[0].isGameControllerSupported == true)
  }

  @Test func overlayDoesNotCopySupportFromADifferentIdentity() {
    let core = snapshot(vendorID: 0x054C, productID: 0x09CC, locationID: 1, supported: nil)
    let probe = snapshot(vendorID: 0x057E, productID: 0x2009, locationID: 1, supported: true)
    let attached = HIDGameControllerSupport.attaching([core], from: [probe])
    #expect(attached[0].isGameControllerSupported == nil)
  }

  @Test func overlayLeavesSupportNilWhenTheSameIdentityIsAmbiguous() {
    let core = snapshot(vendorID: 0x054C, productID: 0x0CE6, locationID: nil, supported: nil)
    let first = snapshot(vendorID: 0x054C, productID: 0x0CE6, locationID: 1, supported: true)
    let second = snapshot(vendorID: 0x054C, productID: 0x0CE6, locationID: 2, supported: false)
    let attached = HIDGameControllerSupport.attaching([core], from: [first, second])
    #expect(attached[0].isGameControllerSupported == nil)
  }

  private func snapshot(
    vendorID: UInt16,
    productID: UInt16,
    locationID: UInt32?,
    supported: Bool?
  ) -> ApplicationServiceHIDGamepadSnapshot {
    ApplicationServiceHIDGamepadSnapshot(
      vendorID: vendorID,
      productID: productID,
      product: "Wireless Controller",
      transport: "USB",
      locationID: locationID,
      serialKind: .ojdUserSpace,
      ioUserClass: nil,
      isOJDUserSpace: true,
      isGameControllerSupported: supported
    )
  }
}
