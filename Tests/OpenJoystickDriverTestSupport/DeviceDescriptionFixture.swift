@testable import OpenJoystickDriverKit

extension ApplicationServiceDeviceDescription {
  /// A USB `hid.descriptor` controller with the given runtime ID, for tests that list controllers.
  package static func fixture(
    id: String,
    name: String = "Test Pad",
    vendorID: UInt16 = 0x045E,
    productID: UInt16 = 0x028E,
    outputs: PhysicalControllerOutputCapabilities = .none,
    unit: String? = nil,
    power: ControllerConnectionState.Power? = nil,
    physicalOutputOwner: ControllerOwnership = .ojd,
    tuning: ControllerTuning = .none
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: name,
      vendorID: vendorID,
      productID: productID,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      physicalOutputCapabilities: outputs,
      physicalOutputOwner: physicalOutputOwner,
      tuning: tuning,
      connectionState: power.map {
        ControllerConnectionState(transport: .usb, backend: .ioHID, isConnected: true, power: $0)
      },
      runtimeIdentifier: id,
      unitIdentifier: unit
    )
  }
}
