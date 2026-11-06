import Foundation

extension DeviceManager {
  /// Tears down the controllers that HID `connection` bound once the backend reports it gone.
  ///
  /// It also forgets the unbound, pass-through and yielded records of the connection and its
  /// pending initialization. A protocol role's disconnect ends only that role. A suspension carries
  /// over when a record reload removed the connection and the backend still lists another one at
  /// its location.
  func handleHIDDeviceDisconnected(connection: HIDDeviceConnection) async {
    clearUnboundDevice(.hid(connection.connectionID))
    clearPassThroughDevice(connection.connectionID)
    yieldedHIDConnections.removeValue(forKey: connection.connectionID)
    let address = connection.routingAddress
    let key = hidInitializationKey(for: connection)
    if hidInitializationTasks[key]?.connection.connectionID == connection.connectionID {
      hidInitializationTasks.removeValue(forKey: key)?.task.cancel()
    }
    // A role's disconnect ends only that role; its siblings at the location keep running.
    let role = hidRoleConnections.removeValue(forKey: connection.connectionID)
    // A record reload, not a physical disconnect, removed this connection; a suspension carries
    // over to the connection that replaces it, while the backend still lists one at the location.
    var keepsSuspension = ownershipCycledHIDConnections.remove(connection.connectionID) != nil
    if keepsSuspension {
      let current = await hidManager.currentConnectionSnapshots() ?? []
      keepsSuspension = current.contains {
        $0.connection.connectionID != connection.connectionID
          && $0.connection.routingAddress == address
      }
    }

    let identifiers = deviceInfos.keys.filter { $0.hidRoutingAddress == address }
    for identifier in identifiers {
      guard role == nil || role == identifier, let info = deviceInfos[identifier],
        case .hid = info.discoverySource, info.hidConnectionID == connection.connectionID,
        info.physicalDevice == connection.physicalDevice
      else { continue }
      let suspended = keepsSuspension && suspendedControllerIdentities.contains(identifier)
      await tearDownHIDDevice(identifier: identifier, connection: connection)
      if suspended, !isStopping { suspendedControllerIdentities.insert(identifier) }
    }
  }

  /// Tears down every HID controller at `address` after a user-requested wireless disconnect.
  ///
  /// The request names the selected ``LogicalControllerID``, not a backend detach event, so the
  /// controllers are found by routing address, and `vendorID` and `productID` serve only the log.
  func handleHIDDeviceDisconnected(
    vendorID: UInt16,
    productID: UInt16,
    address: ControllerConnectionAddress
  ) async {
    for initialization in removeHIDInitializations(at: address) {
      initialization.task.cancel()
    }
    let identifiers = Set(
      pipelines.keys.filter { $0.hidRoutingAddress == address }
        + deviceInfos.keys.filter { $0.hidRoutingAddress == address }
    )
    for identifier in identifiers {
      guard let info = deviceInfos[identifier], case .hid = info.discoverySource else { continue }
      await tearDownHIDDevice(
        identifier: identifier,
        logVendorID: vendorID,
        logProductID: productID
      )
    }
  }

  /// Removes the HID controller `identifier`: neutralizes its physical outputs, sends its
  /// deactivation writes, stops its pipeline and forgets its device information.
  ///
  /// A detach for a `connection` that differs from the device information is ignored as stale.
  /// A physical disconnect ends the user's suspension. Without a `connection`, `logVendorID` and
  /// `logProductID` fill the log line.
  func tearDownHIDDevice(
    identifier: LogicalControllerID,
    connection: HIDDeviceConnection? = nil,
    logVendorID: UInt16? = nil,
    logProductID: UInt16? = nil
  ) async {
    guard let info = deviceInfos[identifier], case .hid = info.discoverySource else { return }
    if let connection,
      info.hidConnectionID != connection.connectionID
        || info.physicalDevice != connection.physicalDevice
    {
      print("[DeviceManager] Ignoring stale HID detach for \(identifier)")
      return
    }
    // A physical disconnect ends the user's suspension; the next connection starts active.
    suspendedControllerIdentities.remove(identifier)

    let pipeline = pipelines.removeValue(forKey: identifier)
    startupPlayerSlots.removeValue(forKey: identifier)
    let outputQueue = hidOutputQueues[identifier]
    hidPeriodicOutputTasks.removeValue(forKey: identifier)?.cancel()
    // Pending output never reaches a disconnected controller; neutralization queues after.
    outputQueue?.cancelAll()
    if let pipeline {
      await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline, detachedInfo: info)
    }
    guard isCurrentHIDDeviceInfo(info, for: identifier), pipelines[identifier] == nil else {
      await pipeline?.stop()
      return
    }
    if let address = identifier.hidRoutingAddress ?? connection?.routingAddress {
      await sendHIDDeactivationWritesIfCurrent(
        pipeline: pipeline,
        address: address,
        identifier: identifier,
        expectedInfo: info
      )
    }
    guard isCurrentHIDDeviceInfo(info, for: identifier), pipelines[identifier] == nil else {
      await pipeline?.stop()
      return
    }
    deviceInfos.removeValue(forKey: identifier)
    notifyServiceStatusChanged()
    lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
    if let outputQueue { retireOutputQueue(for: identifier, expected: outputQueue) }
    await pipeline?.stop()
    await reconcileUnboundHIDClaims()
    let vendorID = connection?.physicalDevice.vendorID ?? logVendorID
    let productID = connection?.physicalDevice.productID ?? logProductID
    let route = connection?.routingAddress ?? identifier.hidRoutingAddress
    print(
      "[DeviceManager] HID device disconnected:" + " VID=\(vendorID.map(String.init) ?? "unknown")"
        + " PID=\(productID.map(String.init) ?? "unknown")"
        + " route=\(route.map { "\($0)" } ?? "unknown")"
    )
  }

  /// Whether `identifier` still has the HID device information `expectedInfo`: the same connection
  /// and physical device.
  func isCurrentHIDDeviceInfo(
    _ expectedInfo: DeviceInfo,
    for identifier: LogicalControllerID
  ) -> Bool {
    guard case .hid = expectedInfo.discoverySource, let currentInfo = deviceInfos[identifier],
      case .hid = currentInfo.discoverySource
    else { return false }
    return currentInfo.hidConnectionID == expectedInfo.hidConnectionID
      && currentInfo.physicalDevice == expectedInfo.physicalDevice
  }

  /// Sends the deactivation writes of `pipeline` to a detaching controller, whose `expectedInfo`
  /// this manager still owns for neutralization.
  private func sendHIDDeactivationWritesIfCurrent(
    pipeline: DevicePipeline?,
    address: ControllerConnectionAddress,
    identifier: LogicalControllerID,
    expectedInfo: DeviceInfo
  ) async {
    guard let pipeline else { return }
    let writes = await pipeline.hidDeactivationWrites()
    _ = await sendHIDWrites(
      writes,
      address: address,
      identifier: identifier,
      pipeline: pipeline,
      detachedInfo: expectedInfo
    )
  }

  /// Sends the deactivation writes of `pipeline` to `address`; does nothing without a pipeline.
  func sendHIDDeactivationWritesIfNeeded(
    pipeline: DevicePipeline?,
    address: ControllerConnectionAddress
  ) async {
    guard let pipeline else { return }
    _ = await sendHIDWrites(
      await pipeline.hidDeactivationWrites(),
      address: address,
      identifier: pipeline.identifier,
      pipeline: pipeline
    )
  }

  /// Feeds one HID element value to the pipeline that the input of `connectionID` routes to.
  func routeHIDElementValue(
    address: ControllerConnectionAddress,
    connectionID: UUID,
    value: HIDElementValue
  ) async {
    guard let key = hidPipelineKey(forInputFrom: connectionID, address: address),
      let pipeline = pipelines[key]
    else { return }
    await pipeline.feedHIDElementValue(value)
  }

  /// Feeds one input report to its pipeline; `laterReportQueued` tells that a later report of
  /// the same connection already waits behind it.
  func routeHIDInputReport(
    address: ControllerConnectionAddress,
    connectionID: UUID,
    data: Data,
    laterReportQueued: Bool = false
  ) async {
    guard let key = hidPipelineKey(forInputFrom: connectionID, address: address),
      let pipeline = pipelines[key], let info = deviceInfos[key], case .hid = info.discoverySource,
      let physicalDevice = info.physicalDevice, let boundConnectionID = info.hidConnectionID
    else { return }
    let connection = HIDDeviceConnection(
      connectionID: boundConnectionID,
      physicalDevice: physicalDevice,
      routingAddress: address
    )
    let connectionWrites = await pipeline.feedHIDData(data, laterReportQueued: laterReportQueued)
    guard pipelines[key] === pipeline,
      isCurrentHIDStartupConnection(pipeline, connection: connection)
    else { return }
    _ = await sendHIDWrites(
      connectionWrites,
      address: address,
      identifier: key,
      pipeline: pipeline,
      startupConnection: connection
    )
    // A controller OJD serves holds the slot it was admitted with; one macOS serves claims it here.
    guard await pipeline.takeStartupPlayerIndicatorDue(), pipelines[key] === pipeline,
      let indicator = pipeline.startupPlayerIndicator ?? claimStartupPlayerSlot(for: key)
    else { return }
    let result = await sendControllerOutput(.setPlayerIndicator(indicator), toConnected: key)
    // On a controller OJD serves the slot is startup output, so the controller details show it.
    guard !pipeline.observesOnly else { return }
    await pipeline.recordStartupOutputStatus(result.outcome == .delivered ? "succeeded" : "failed")
  }

  /// The lowest player slot no other native controller holds, kept for `identifier` until it
  /// detaches; nil when all four are taken.
  func claimStartupPlayerSlot(for identifier: LogicalControllerID) -> PhysicalPlayerIndicator? {
    if let held = startupPlayerSlots[identifier] { return held }
    let taken = Set(startupPlayerSlots.values)
    guard
      let slot = PhysicalPlayerIndicator.allCases.first(where: { $0 != .off && !taken.contains($0) }
      )
    else { return nil }
    startupPlayerSlots[identifier] = slot
    return slot
  }
}
