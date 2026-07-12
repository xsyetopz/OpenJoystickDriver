import OpenJoystickDriverKit

/// Shared XPC surface for CLI and GUI controller-input diagnostics.
actor ControllerInputDiagnosticService {
  private let client: XPCClient

  init(client: XPCClient = XPCClient()) {
    self.client = client
    client.connect()
  }

  func disconnect() {
    client.disconnect()
  }

  func connectedDevices() async throws -> [XPCDeviceDescription] {
    try await client.getStatus().connectedDevices
  }

  func deviceInputState(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> DeviceInputState? {
    try await client.deviceInputState(vendorID: vendorID, productID: productID)
  }

  func packetLog(
    vendorID: UInt16,
    productID: UInt16
  ) async throws -> [PacketLogEntry] {
    try await client.packetLog(vendorID: vendorID, productID: productID)
  }
}
