import Foundation

extension DeviceManager {
  public func suspendController(
    _ controller: ControllerReference
  ) async -> ControllerSuspendResult {
    guard
      let identifier = await connectedIdentifier(for: controller),
      let pipeline = pipelines[identifier]
    else { return ControllerSuspendResult(state: .active, failure: .notFound) }
    guard await pipeline.controllerSessionState() == .active else {
      return ControllerSuspendResult(state: .suspended, failure: .alreadySuspended)
    }
    await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
    guard await pipeline.suspendControllerSession() else {
      return ControllerSuspendResult(state: .active, failure: .notFound)
    }
    suspendedControllerIdentities.insert(identifier)
    notifyServiceStatusChanged()
    return ControllerSuspendResult(state: .suspended)
  }

  public func resumeController(
    _ controller: ControllerReference
  ) async -> ControllerResumeResult {
    guard
      let identifier = await connectedIdentifier(for: controller),
      let pipeline = pipelines[identifier], let info = deviceInfos[identifier]
    else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
    let hidConnection: HIDDeviceConnection?
    switch info.discoverySource {
    case .hid:
      guard let physicalDevice = info.physicalDevice, let connectionID = info.hidConnectionID,
        let address = identifier.hidRoutingAddress
      else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
      hidConnection = HIDDeviceConnection(
        connectionID: connectionID,
        physicalDevice: physicalDevice,
        routingAddress: address
      )
    case .rawUSB: hidConnection = nil
    }
    guard await pipeline.controllerSessionState() == .suspended else {
      return ControllerResumeResult(state: .active, failure: .alreadyActive)
    }
    guard pipelines[identifier] === pipeline,
      hidConnection.map({ isCurrentHIDStartupConnection(pipeline, connection: $0) }) ?? true
    else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
    guard await pipeline.restartUSBStartupOutputForResume() else {
      return ControllerResumeResult(state: .suspended, failure: .notFound)
    }
    guard pipelines[identifier] === pipeline,
      hidConnection.map({ isCurrentHIDStartupConnection(pipeline, connection: $0) }) ?? true
    else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
    if await pipeline.requiresSuccessfulHIDStartupOutput() {
      guard let hidConnection,
        await isCurrentHIDStartupPipeline(pipeline, connection: hidConnection)
      else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
      guard await sendHIDStartupOutputReportsIfNeeded(pipeline: pipeline, connection: hidConnection)
      else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
      guard await isCurrentHIDStartupPipeline(pipeline, connection: hidConnection) else {
        return ControllerResumeResult(state: .suspended, failure: .notFound)
      }
    }
    guard pipelines[identifier] === pipeline,
      hidConnection.map({ isCurrentHIDStartupConnection(pipeline, connection: $0) }) ?? true
    else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
    guard await pipeline.resumeControllerSession() else {
      return ControllerResumeResult(state: .suspended, failure: .notFound)
    }
    guard pipelines[identifier] === pipeline,
      hidConnection.map({ isCurrentHIDStartupConnection(pipeline, connection: $0) }) ?? true
    else { return ControllerResumeResult(state: .suspended, failure: .notFound) }
    suspendedControllerIdentities.remove(identifier)
    notifyServiceStatusChanged()
    return ControllerResumeResult(state: .active)
  }

  public func disconnectWirelessController(
    _ controller: ControllerReference,
    timeoutNanoseconds: UInt64 = UInt64(ServiceTimeouts.bluetoothDisconnect * 1_000_000_000)
  ) async -> WirelessControllerDisconnectResult {
    guard
      let identifier = await connectedIdentifier(for: controller),
      let pipeline = pipelines[identifier], let info = deviceInfos[identifier]
    else { return WirelessControllerDisconnectResult(state: .active, failure: .notFound) }
    // CoreBluetooth cancels only connections the calling app holds, and IOBluetooth closes only
    // classic baseband links, so a system-connected Bluetooth LE HID link has no supported
    // disconnect path.
    let transport = await pipeline.currentConnectionState()?.transport
    guard transport == .bluetoothClassic else {
      return WirelessControllerDisconnectResult(
        state: await pipeline.controllerSessionState(),
        failure: transport == .bluetoothLE ? .bluetoothLEUnsupported : .notBluetooth
      )
    }
    guard let address = Self.bluetoothAddress(from: info.serialNumber),
      let routingAddress = identifier.hidRoutingAddress
    else {
      return WirelessControllerDisconnectResult(
        state: await pipeline.controllerSessionState(),
        failure: .missingAddress
      )
    }
    guard let wirelessControllerDisconnector else {
      return WirelessControllerDisconnectResult(
        state: await pipeline.controllerSessionState(),
        failure: .disconnectFailed
      )
    }

    await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
    let priorState = await pipeline.controllerSessionState()
    if await pipeline.controllerSessionState() == .active {
      guard await pipeline.suspendControllerSession() else {
        return WirelessControllerDisconnectResult(state: .active, failure: .notFound)
      }
    }

    let claimResult = await hidManager.releaseInputClaim(address: routingAddress)
    if case .failed = claimResult {
      if priorState == .active { _ = await pipeline.resumeControllerSession() }
      notifyServiceStatusChanged()
      return WirelessControllerDisconnectResult(
        state: await pipeline.controllerSessionState(),
        failure: .disconnectFailed,
        failedStage: .releaseHIDClaim,
        detail: Self.hidClaimFailureDescription(claimResult),
        recovery: "Reconnect the controller if input does not resume."
      )
    }
    let claimWasReleased = claimResult == .released

    switch await wirelessControllerDisconnector.disconnect(
      address: address,
      timeoutNanoseconds: timeoutNanoseconds
    ) {
    case .disconnected:
      await handleHIDDeviceDisconnected(
        vendorID: identifier.model.vendorID,
        productID: identifier.model.productID,
        address: routingAddress
      )
      return WirelessControllerDisconnectResult(state: .suspended)
    case .failed(let code):
      return await restoreAfterFailedWirelessDisconnect(
        identifier: identifier,
        pipeline: pipeline,
        priorState: priorState,
        failure: .disconnectFailed,
        stage: .closeBluetoothConnection,
        code: code,
        detail: "IOBluetoothDevice.closeConnection failed with I/O code \(code).",
        restoreHIDClaim: claimWasReleased
      )
    case .stillConnected:
      return await restoreAfterFailedWirelessDisconnect(
        identifier: identifier,
        pipeline: pipeline,
        priorState: priorState,
        failure: .disconnectFailed,
        stage: .confirmBluetoothDisconnection,
        detail: "Bluetooth reported that the controller remained connected after closeConnection.",
        restoreHIDClaim: claimWasReleased
      )
    case .timedOut:
      return await restoreAfterFailedWirelessDisconnect(
        identifier: identifier,
        pipeline: pipeline,
        priorState: priorState,
        failure: .timedOut,
        stage: .confirmBluetoothDisconnection,
        detail: "Bluetooth disconnection was not confirmed before the timeout.",
        restoreHIDClaim: claimWasReleased
      )
    }
  }

  func restoreAfterFailedWirelessDisconnect(
    identifier: LogicalControllerID,
    pipeline: DevicePipeline,
    priorState: ControllerSessionState,
    failure: WirelessControllerDisconnectFailure,
    stage: WirelessControllerDisconnectStage,
    code: Int32? = nil,
    detail: String,
    restoreHIDClaim: Bool
  ) async -> WirelessControllerDisconnectResult {
    let claimResult: PhysicalHIDClaimResult =
      if restoreHIDClaim, let routingAddress = identifier.hidRoutingAddress {
        await hidManager.reacquireInputClaim(address: routingAddress)
      } else {
        .reacquired
      }
    guard claimResult == .reacquired else {
      return WirelessControllerDisconnectResult(
        state: .suspended,
        failure: failure,
        failedStage: .restoreHIDClaim,
        systemCode: code,
        detail: "\(detail) HID recovery failed: \(Self.hidClaimFailureDescription(claimResult)).",
        recovery: "Reconnect the controller to restore input."
      )
    }
    if priorState == .active, !(await pipeline.resumeControllerSession()) {
      return WirelessControllerDisconnectResult(
        state: .suspended,
        failure: failure,
        failedStage: .restoreControllerSession,
        systemCode: code,
        detail: "\(detail) The HID claim was restored, but the controller session did not resume.",
        recovery: "Reconnect the controller to restore OpenJoystickDriver output."
      )
    }
    notifyServiceStatusChanged()
    return WirelessControllerDisconnectResult(
      state: priorState,
      failure: failure,
      failedStage: stage,
      systemCode: code,
      detail: detail,
      recovery: "The previous controller session was restored; retry or reconnect the controller."
    )
  }

  static func hidClaimFailureDescription(_ result: PhysicalHIDClaimResult) -> String {
    switch result {
    case .released: "released"
    case .reacquired: "reacquired"
    case .unavailable: "the HID claim was unavailable"
    case .failed(let failure): failure.description
    }
  }

  static func bluetoothAddress(from serialNumber: String?) -> String? {
    guard let serialNumber else { return nil }
    let hexadecimal = serialNumber.filter(\.isHexDigit)
    guard hexadecimal.count == 12,
      serialNumber.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "-" })
    else { return nil }
    return stride(from: 0, to: hexadecimal.count, by: 2).map { offset in
      let start = hexadecimal.index(hexadecimal.startIndex, offsetBy: offset)
      let end = hexadecimal.index(start, offsetBy: 2)
      return hexadecimal[start..<end].uppercased()
    }.joined(separator: ":")
  }
}
