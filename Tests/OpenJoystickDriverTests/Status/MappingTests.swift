import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

struct StatusMappingTests {
  @Test func mapsPermissionStatesWithoutTreatingUnknownAsDenied() {
    let snapshot = RuntimeStatusSnapshot(
      payload: payload(inputMonitoring: "denied", accessibility: "unknown")
    )

    #expect(snapshot.permissions.inputMonitoring == .denied)
    #expect(snapshot.permissions.accessibility == .unknown)
    #expect(!snapshot.permissions.isReady)
    #expect(snapshot.permissions.isAvailable)
  }

  @Test func marksPermissionStateUnavailableWithoutRuntimeOrLocalEvidence() {
    let snapshot = RuntimeStatusSnapshot.unavailable

    #expect(snapshot.permissions.inputMonitoring == .unavailable)
    #expect(snapshot.permissions.accessibility == .unavailable)
    #expect(!snapshot.permissions.isAvailable)
  }

  @Test func mapsOutputErrorSeparatelyFromItsDiagnostic() {
    let snapshot = RuntimeStatusSnapshot(
      payload: payload(enabled: false, outputStatus: "error: Accessibility denied")
    )

    #expect(snapshot.output.state == .error)
    #expect(snapshot.output.diagnostic == "Accessibility denied")
    #expect(snapshot.output.detail == nil)
  }

  @Test func distinguishesEnabledDisabledAndUnavailableOutput() {
    #expect(CompatibilityOutputStatus(enabled: true, status: "on").state == .enabled)
    #expect(CompatibilityOutputStatus(enabled: false, status: "off").state == .disabled)
    #expect(CompatibilityOutputStatus(enabled: nil, status: nil).state == .unavailable)
    #expect(CompatibilityOutputStatus(enabled: false, status: "unknown").state == .unavailable)
  }

  @Test func mapsOnlyKnownCompatibilityIdentityValues() {
    let known = RuntimeStatusSnapshot(payload: payload(identity: "apple-gamecontroller"))
    let invalid = RuntimeStatusSnapshot(payload: payload(identity: "future-profile"))

    #expect(known.compatibility.identity == .appleGameController)
    #expect(known.compatibility.diagnostic == nil)
    #expect(invalid.compatibility.identity == nil)
    #expect(invalid.compatibility.diagnostic == "Unknown compatibility identity: future-profile")
  }

  @Test func wrapsControllerDescriptionsWithoutSynthesizingContractIdentity() {
    let description = ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GenericHID",
      connection: "USB",
      serialNumber: nil
    )
    let snapshot = RuntimeStatusSnapshot(payload: payload(devices: [description]))

    #expect(snapshot.controllers.isAvailable)
    #expect(snapshot.controllers.count == 1)
    #expect(snapshot.controllers.descriptions.first?.name == "Test Controller")
    #expect(snapshot.controllers.descriptions.first?.serialNumber == nil)
  }

  private func payload(
    inputMonitoring: String = "granted",
    accessibility: String = "granted",
    devices: [ApplicationServiceDeviceDescription] = [],
    enabled: Bool? = true,
    outputStatus: String? = "on",
    identity: String? = "sdl2-3"
  ) -> ApplicationServiceStatusPayload {
    ApplicationServiceStatusPayload(
      inputMonitoring: inputMonitoring,
      accessibility: accessibility,
      connectedDevices: devices,
      userSpaceVirtualDeviceEnabled: enabled,
      userSpaceVirtualDeviceStatus: outputStatus,
      compatibilityIdentity: identity
    )
  }
}
