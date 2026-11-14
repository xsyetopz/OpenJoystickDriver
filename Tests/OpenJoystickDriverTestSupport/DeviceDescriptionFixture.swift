@testable package import OpenJoystickDriverKit

extension ControllerSessionToken {
  /// The token `E-` and `label` padded with `0` to 16 characters, so tests can name one.
  package static func fixture(_ label: String) -> ControllerSessionToken {
    let body = label + String(repeating: "0", count: max(0, 16 - label.count))
    guard let token = ControllerSessionToken(rawValue: prefix + body) else {
      preconditionFailure("A token label is at most 16 base64url characters.")
    }
    return token
  }
}

/// The session token text of the fixture controller `label`, as the runtime reports it.
package func token(_ label: String) -> String { ControllerSessionToken.fixture(label).rawValue }

extension ControllerPortKey {
  /// The port key `U-` and `label` padded with `0` to 16 characters, so tests can name one.
  package static func fixture(_ label: String) -> ControllerPortKey {
    let body = label + String(repeating: "0", count: max(0, 16 - label.count))
    guard let portKey = ControllerPortKey(rawValue: prefix + body) else {
      preconditionFailure("A port key label is at most 16 base64url characters.")
    }
    return portKey
  }
}

extension ApplicationServiceDeviceDescription {
  /// A USB controller whose session token is `.fixture(id)`, bound to `protocolBinding`
  /// (`HIDDescriptor` unless a test names another), for tests that list controllers.
  package static func fixture(
    id: String,
    name: String = "Test Pad",
    vendorID: UInt16 = 0x045E,
    productID: UInt16 = 0x028E,
    serialNumber: String? = nil,
    outputs: PhysicalControllerOutputCapabilities = .none,
    unit: String? = nil,
    power: ControllerConnectionState.Power? = nil,
    inputHealth: ControllerInputHealth = ControllerInputHealth(state: .healthy),
    physicalOwnership: ControllerOwnershipObservation = .unknown,
    sessionState: ControllerSessionState = .active,
    hidInputOwnership: HIDInputOwnership = .unknown,
    inputOwner: USBExclusiveOwner? = nil,
    duplicateExposureRisk: DuplicateExposureRisk = .unknownOwnership,
    physicalOutputOwner: ControllerServer = .ojd,
    tuning: ControllerTuning = .none,
    protocolBinding: ProtocolBindingID = ProtocolBindingID(.hidDescriptor),
    bindingResult: ProtocolBindingResult = .hidDescriptorFixture
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      protocolBinding: protocolBinding,
      connection: "USB",
      discoverySource: .rawUSB,
      physicalOwnership: physicalOwnership,
      hidInputOwnership: hidInputOwnership,
      inputOwner: inputOwner,
      duplicateExposureRisk: duplicateExposureRisk,
      serialNumber: serialNumber,
      bindingResult: bindingResult,
      physicalOutputCapabilities: outputs,
      physicalOutputOwner: physicalOutputOwner,
      recordServer: .system,
      recordAccessRoute: .system,
      tuning: tuning,
      connectionState: power.map {
        ControllerConnectionState(transport: .usb, backend: .hid, isConnected: true, power: $0)
      },
      sessionState: sessionState,
      inputHealth: inputHealth,
      sessionToken: .fixture(id),
      portKey: unit.map(ControllerPortKey.fixture)
    )
  }
}
