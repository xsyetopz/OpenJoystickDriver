import CoreHID
import Foundation
import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

struct AppleGameControllerSyntheticHIDTests {
  @Test func matchingExclusionUsesAppleSyntheticPropertyKey() {
    #expect(AppleGameControllerSyntheticHID.propertyKey == "GCSyntheticDevice")
    let matching = AppleGameControllerSyntheticHID.ioHIDMatchingExcludingSynthetics([
      kIOHIDVendorIDKey as String: 0x045E
    ])
    #expect(matching[kIOHIDVendorIDKey as String] as? Int == 0x045E)
    #expect(matching[AppleGameControllerSyntheticHID.propertyKey] as? Bool == false)
    #expect(
      !AppleGameControllerSyntheticHID.isSyntheticProperty(
        matching[AppleGameControllerSyntheticHID.propertyKey]
      )
    )
  }

  @Test func matchAllReplacementExcludesSyntheticsWithoutOpening() {
    let matching = AppleGameControllerSyntheticHID.allHIDDevicesExcludingSynthetics
    #expect(matching[kIOProviderClassKey as String] as? String == kIOHIDDeviceKey as String)
    #expect(matching[AppleGameControllerSyntheticHID.propertyKey] as? Bool == false)
  }

  @Test func signatureClassificationDoesNotOpenADevice() {
    #expect(AppleGameControllerSyntheticHID.ioClassName == "AppleGCSyntheticDevice")
    #expect(AppleGameControllerSyntheticHID.xbox360DeviceType == "Xbox360Controller")
    #expect(
      AppleGameControllerSyntheticHID.isSyntheticDevice(className: "AppleGCSyntheticDevice")
    )
    #expect(AppleGameControllerSyntheticHID.isSyntheticDevice(productName: "GamePad-1"))
    #expect(
      AppleGameControllerSyntheticHID.isSyntheticDevice(deviceType: "Xbox360Controller")
    )
    #expect(
      AppleGameControllerSyntheticHID.isSyntheticDevice(syntheticProperty: kCFBooleanTrue)
    )
    #expect(
      AppleGameControllerSyntheticHID.isSyntheticDevice(
        pluginPath:
          "AppleSyntheticGameController.kext/Contents/PlugIns/AppleSyntheticGameController.plugin"
      )
    )
    #expect(
      !AppleGameControllerSyntheticHID.isSyntheticDevice(
        className: "IOHIDUserDevice",
        productName: "Xbox Wireless Controller",
        syntheticProperty: kCFBooleanFalse
      )
    )
    #expect(!AppleGameControllerSyntheticHID.isSynthetic(service: 0))
  }

  @Test func unknownRegistryEntryLookupDoesNotOpenAUserClient() {
    #expect(!AppleGameControllerSyntheticHID.isSyntheticRegistryEntry(id: 0))
    #expect(!AppleGameControllerSyntheticHID.isSyntheticRegistryEntry(id: 1))
  }

  @Test func physicalAdmissionRejectsGamePad1WithoutSyntheticBoolean() {
    #expect(
      !PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: nil,
        productName: "GamePad-1",
        transport: "USB",
        locationID: 1_114_112,
        syntheticProperty: nil
      )
    )
    #expect(
      PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: "physical-serial",
        productName: "Xbox Wireless Controller",
        transport: "USB",
        locationID: 1_114_112,
        syntheticProperty: kCFBooleanFalse
      )
    )
  }

  @available(macOS 15, *)
  @Test func coreHIDMatchingCriteriaCarrySyntheticExclusion() {
    let criteria = AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
      primaryUsage: .genericDesktop(.gamepad)
    )
    #expect(criteria.primaryUsage == .genericDesktop(.gamepad))
    let vidPid = AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
      vendorID: 0x045E,
      productID: 0x0B13
    )
    #expect(vidPid.vendorID == 0x045E)
    #expect(vidPid.productID == 0x0B13)
  }
}
