import Foundation

extension ApplicationServiceClient {

  /// Connects to the running main app, waiting up to `timeoutSeconds` for its local server.
  ///
  /// The client never launches the app. Cancelling the calling task stops the retries and leaves
  /// the client disconnected.
  public func connect(timeoutSeconds: TimeInterval = 5) async {
    let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
    do { if try await waitForLocalServer(until: deadline) { return } } catch {}
    stateLock.withLock { connected = false }
  }

  public func disconnect() { stateLock.withLock { connected = false } }

  public var isConnected: Bool { stateLock.withLock { connected } }

  public func listDevices() async throws -> [String] {
    try await call(.listDevices, LocalServiceRPCEmptyArguments())
  }

  public func getStatus() async throws -> ApplicationServiceStatusPayload {
    let data: Data = try await call(.getStatus, LocalServiceRPCEmptyArguments())
    guard let payload = try? JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func requestRequiredAccess() async throws -> PermissionManager.Snapshot {
    try await call(.requestRequiredAccess, LocalServiceRPCEmptyArguments())
  }

  public func requestAccess(
    _ requirement: PermissionManager.Requirement
  ) async throws -> PermissionManager.Snapshot {
    try await call(.requestAccess, LocalServiceRPCPermissionArguments(requirement: requirement))
  }

  public func controllerState(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> ControllerState? {
    let data: Data? = try await call(
      .getControllerState,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let data else { return nil }
    return try? JSONDecoder().decode(ControllerState.self, from: data)
  }

  public func packetLog(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> [PacketLogEntry] {
    let data: Data = try await call(
      .getPacketLog,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let entries = try? JSONDecoder().decode([PacketLogEntry].self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return entries
  }

  /// Sends one output command to the selected controller through the running app.
  public func sendControllerOutput(
    _ command: ControllerOutputCommand,
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> ControllerOutputResult {
    try await call(
      .sendControllerOutput,
      LocalServiceRPCControllerOutputArguments(
        vendorID: vendorID,
        productID: productID,
        runtimeIdentifier: runtimeIdentifier,
        command: command
      )
    )
  }

  public func previewPhysicalColor(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
    token: UUID,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    try await call(
      .previewPhysicalColor,
      LocalServiceRPCColorPreviewArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        token: token,
        red: Int(red),
        green: Int(green),
        blue: Int(blue)
      )
    )
  }

  public func releasePhysicalColorPreview(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
    token: UUID
  ) async throws -> Bool {
    try await call(
      .releasePhysicalColorPreview,
      LocalServiceRPCColorPreviewReleaseArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        token: token
      )
    )
  }

  public func setSuppressOutput(_ suppress: Bool) async throws {
    let _: Bool = try await call(.setSuppressOutput, LocalServiceRPCBoolArguments(value: suppress))
  }

  public func getVirtualDeviceDiagnostics() async throws
    -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    let data: Data = try await call(.getVirtualDeviceDiagnostics, LocalServiceRPCEmptyArguments())
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceDiagnosticsPayload.self,
        from: data
      )
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  /// Stores `profile` as the virtual HID profile override for the selected controller's model
  /// and applies it to the connected controller.
  public func setVirtualHIDProfileOverride(
    _ profile: String,
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> VirtualHIDProfileOverrideResult {
    try await call(
      .setVirtualHIDProfileOverride,
      LocalServiceRPCVirtualHIDProfileOverrideArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        profile: profile
      )
    )
  }

  /// Returns the selected controller's model to automatic virtual HID profile selection.
  public func resetVirtualHIDProfileOverride(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> VirtualHIDProfileOverrideResult {
    try await call(
      .resetVirtualHIDProfileOverride,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
  }

  public func suspendController(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) async throws -> ControllerSuspendResult {
    let data: Data = try await call(
      .suspendController,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let result = try? JSONDecoder().decode(ControllerSuspendResult.self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return result
  }

  public func resumeController(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) async throws -> ControllerResumeResult {
    let data: Data = try await call(
      .resumeController,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let result = try? JSONDecoder().decode(ControllerResumeResult.self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return result
  }

  public func disconnectWirelessController(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String?
  ) async throws -> WirelessControllerDisconnectResult {
    let data: Data = try await call(
      .disconnectWirelessController,
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      ),
      timeoutSeconds: 5
    )
    guard
      let result = try? JSONDecoder().decode(WirelessControllerDisconnectResult.self, from: data)
    else { throw ApplicationServiceClientError.invalidResponse }
    return result
  }

  public func runVirtualDeviceSelfTest(
    seconds: Int
  ) async throws -> ApplicationServiceVirtualDeviceSelfTestPayload {
    let clampedSeconds = max(1, min(30, seconds))
    let data: Data = try await call(
      .runVirtualDeviceSelfTest,
      LocalServiceRPCIntArguments(value: clampedSeconds),
      timeoutSeconds: TimeInterval(clampedSeconds) + applicationServiceSelfTestReplyGraceSeconds
    )
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceSelfTestPayload.self,
        from: data
      )
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func resetSettings() async throws -> Bool {
    try await call(.resetSettings, LocalServiceRPCEmptyArguments())
  }

  /// Reads every app setting.
  public func getSettings() async throws -> ApplicationSettingsPayload {
    try await call(.getSettings, LocalServiceRPCEmptyArguments())
  }

  /// Applies one app setting and returns every setting as it stands afterward, because macOS can
  /// leave a setting off, such as a login item that needs approval.
  public func setSetting(
    _ key: ApplicationSettingKey,
    to value: Bool
  ) async throws -> ApplicationSettingsPayload {
    try await call(.setSetting, ApplicationServiceSettingArguments(key: key, value: value))
  }

  public func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await call(.getRemappingSnapshot, LocalServiceRPCEmptyArguments())
  }

  public func remappingMotionCalibration(
    runtimeIdentifier: String,
    command: RemappingMotionCalibrationCommand? = nil
  ) async throws -> RemappingMotionCalibrationStatus {
    try await call(
      .remappingMotionCalibration,
      ApplicationServiceMotionCalibrationArguments(
        runtimeIdentifier: runtimeIdentifier,
        command: command
      )
    )
  }
}
