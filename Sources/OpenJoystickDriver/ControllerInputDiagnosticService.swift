import OpenJoystickDriverKit

/// Shared application-service surface for CLI controller-input diagnostics.
actor ControllerInputDiagnosticService {
  private let client: ApplicationServiceClient

  init(client: ApplicationServiceClient = ApplicationServiceClient()) {
    self.client = client
    client.connect()
  }

  func disconnect() {
    client.disconnect()
  }

  func connectedDevices() async throws -> [ApplicationServiceDeviceDescription] {
    try await client.getStatus().connectedDevices
  }

  func deviceInputState(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> DeviceInputState? {
    try await client.deviceInputState(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }

  func packetLog(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> [PacketLogEntry] {
    try await client.packetLog(
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier
    )
  }
}
