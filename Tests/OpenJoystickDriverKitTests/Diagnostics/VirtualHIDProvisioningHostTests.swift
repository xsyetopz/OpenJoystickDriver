import Foundation
import Testing

@testable import OpenJoystickDriverKit

struct VirtualHIDProvisioningHostTests {
  private let provisioningUDID = "00001111-0011111111111111"
  private let hardwareUUID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
  private let otherID = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"

  @Test func missingDeviceListIsUnrestricted() {
    #expect(
      VirtualHIDProvisioningHost.authorization(profilePlist: [:], hostIDs: [hardwareUUID])
        == .unrestricted
    )
  }

  @Test func provisionsAllDevicesIsUnrestricted() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionsAllDevices": true, "ProvisionedDevices": [otherID]],
        hostIDs: [hardwareUUID]
      ) == .unrestricted
    )
  }

  @Test func provisioningUDIDMatchIsIncluded() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [provisioningUDID]],
        hostIDs: [hardwareUUID, provisioningUDID]
      ) == .includesHost
    )
  }

  @Test func hardwareUUIDMatchIsIncluded() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [hardwareUUID]],
        hostIDs: [hardwareUUID, provisioningUDID]
      ) == .includesHost
    )
  }

  @Test func hyphenAndCaseDifferencesStillMatch() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [provisioningUDID]],
        hostIDs: ["000011110011111111111111"]
      ) == .includesHost
    )
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [hardwareUUID.lowercased()]],
        hostIDs: [hardwareUUID]
      ) == .includesHost
    )
  }

  @Test func unlistedHostIsExcluded() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [otherID]],
        hostIDs: [hardwareUUID, provisioningUDID]
      ) == .excludesHost
    )
  }

  @Test func listedDevicesWithoutHostIDsAreUnavailable() {
    #expect(
      VirtualHIDProvisioningHost.authorization(
        profilePlist: ["ProvisionedDevices": [provisioningUDID]],
        hostIDs: []
      ) == .unavailable
    )
  }
}
