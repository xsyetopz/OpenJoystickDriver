import Foundation

extension DeviceManager {
  func handleHIDDeviceDisconnected(connection: HIDDeviceConnection) async {
    clearUnboundDevice(.hid(connection.connectionID))
    clearPassThroughDevice(connection.connectionID)
    yieldedHIDConnections.removeValue(forKey: connection.connectionID)
    let locationID = connection.routingLocationID
    let key = hidInitializationKey(for: connection)
    if hidInitializationTasks[key]?.connection.connectionID == connection.connectionID {
      hidInitializationTasks.removeValue(forKey: key)?.task.cancel()
    }
    // A role's disconnect ends only that role; its siblings at the location keep running.
    let role = hidRoleConnections.removeValue(forKey: connection.connectionID)

    let identifiers = deviceInfos.keys.filter { $0.locationID == locationID }
    for identifier in identifiers {
      guard role == nil || role == identifier, let info = deviceInfos[identifier],
        case .hid = info.discoverySource, info.hidConnectionID == connection.connectionID,
        info.physicalDevice == connection.physicalDevice
      else { continue }
      await tearDownHIDDevice(identifier: identifier, connection: connection)
    }
  }

  /// User-requested wireless disconnects are keyed by the selected DeviceIdentifier, not by a
  /// backend detach event. They retain their existing location-scoped behavior.
  func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32) async {
    for initialization in removeHIDInitializations(atLocation: locationID) {
      initialization.task.cancel()
    }
    let identifiers = Set(
      pipelines.keys.filter { $0.locationID == locationID }
        + deviceInfos.keys.filter { $0.locationID == locationID }
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

  func tearDownHIDDevice(
    identifier: DeviceIdentifier,
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
    await sendHIDDeactivationWritesIfCurrent(
      pipeline: pipeline,
      locationID: identifier.locationID ?? connection?.routingLocationID ?? 0,
      identifier: identifier,
      expectedInfo: info
    )
    guard isCurrentHIDDeviceInfo(info, for: identifier), pipelines[identifier] == nil else {
      await pipeline?.stop()
      return
    }
    deviceInfos.removeValue(forKey: identifier)
    notifyControllerInventoryChanged()
    lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
    if let outputQueue { retireOutputQueue(for: identifier, expected: outputQueue) }
    await pipeline?.stop()
    await reconcileUnboundHIDClaims()
    let vendorID = connection?.physicalDevice.vendorID ?? logVendorID
    let productID = connection?.physicalDevice.productID ?? logProductID
    print(
      "[DeviceManager] HID device disconnected:" + " VID=\(vendorID.map(String.init) ?? "unknown")"
        + " PID=\(productID.map(String.init) ?? "unknown")"
        + " loc=\(connection?.routingLocationID ?? identifier.locationID ?? 0)"
    )
  }

  func isCurrentHIDDeviceInfo(_ expectedInfo: DeviceInfo, for identifier: DeviceIdentifier) -> Bool
  {
    guard case .hid = expectedInfo.discoverySource, let currentInfo = deviceInfos[identifier],
      case .hid = currentInfo.discoverySource
    else { return false }
    return currentInfo.hidConnectionID == expectedInfo.hidConnectionID
      && currentInfo.physicalDevice == expectedInfo.physicalDevice
  }

  private func sendHIDDeactivationWritesIfCurrent(
    pipeline: DevicePipeline?,
    locationID: UInt32,
    identifier: DeviceIdentifier,
    expectedInfo: DeviceInfo
  ) async {
    guard let pipeline else { return }
    let writes = await pipeline.hidDeactivationWrites()
    _ = await sendHIDWrites(
      writes,
      locationID: locationID,
      identifier: identifier,
      pipeline: pipeline,
      detachedInfo: expectedInfo
    )
  }

  func sendHIDDeactivationWritesIfNeeded(pipeline: DevicePipeline?, locationID: UInt32) async {
    guard let pipeline else { return }
    _ = await sendHIDWrites(
      await pipeline.hidDeactivationWrites(),
      locationID: locationID,
      identifier: pipeline.identifier,
      pipeline: pipeline
    )
  }

  func routeHIDElementValue(locationID: UInt32, connectionID: UUID, value: HIDElementValue) async {
    guard let key = hidPipelineKey(forInputFrom: connectionID, locationID: locationID),
      let pipeline = pipelines[key]
    else { return }
    await pipeline.feedHIDElementValue(value)
  }

  func routeHIDInputReport(locationID: UInt32, connectionID: UUID, data: Data) async {
    guard let key = hidPipelineKey(forInputFrom: connectionID, locationID: locationID),
      let pipeline = pipelines[key], let info = deviceInfos[key], case .hid = info.discoverySource,
      let physicalDevice = info.physicalDevice, let boundConnectionID = info.hidConnectionID
    else { return }
    let connection = HIDDeviceConnection(
      connectionID: boundConnectionID,
      physicalDevice: physicalDevice,
      routingLocationID: locationID
    )
    let connectionWrites = await pipeline.feedHIDData(data)
    guard pipelines[key] === pipeline,
      isCurrentHIDStartupConnection(pipeline, connection: connection)
    else { return }
    _ = await sendHIDWrites(
      connectionWrites,
      locationID: locationID,
      identifier: key,
      pipeline: pipeline,
      startupConnection: connection
    )
    guard pipeline.nativeWrites?.setsStartupPlayerIndicator == true,
      await pipeline.takeStartupPlayerIndicatorDue(), pipelines[key] === pipeline,
      let indicator = claimStartupPlayerSlot(for: key)
    else { return }
    _ = await sendControllerOutput(
      .setPlayerIndicator(indicator),
      for: key,
      runtimeIdentifier: key.runtimeIdentifier
    )
  }

  /// The lowest player slot no other native controller holds, kept for `identifier` until it
  /// detaches; nil when all four are taken.
  func claimStartupPlayerSlot(for identifier: DeviceIdentifier) -> PhysicalPlayerIndicator? {
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
