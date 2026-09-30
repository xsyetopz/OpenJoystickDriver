import Foundation

/// One protocol role of a raw-USB service, validated before its pipeline exists. Its driver is
/// built again when the pipeline is created, since a driver is not sendable across the actor
/// suspensions between roles; construction is pure, so it repeats the validated result.
struct USBRoleAdmission {
  let identifier: DeviceIdentifier
  let resolution: USBTransportResolution
  let slotOrdinal: Int
}

extension DeviceManager {
  /// Whether a raw-USB role of this exact enumerated service is still in the inventory.
  func isRunningUSBRole(_ identifier: DeviceIdentifier, of device: USBTransportDevice) -> Bool {
    guard let info = deviceInfos[identifier], case .rawUSB(let route) = info.discoverySource else {
      return false
    }
    return route == device.route && info.usbTransportDevice == device
  }

  /// Starts every role of one service as its own pipeline and logical controller, or none of
  /// them: when a role meets a retry condition, the roles already started are stopped and the
  /// service stays unacknowledged, so the next poll admits it whole.
  func startUSBRoles(
    _ roles: [USBRoleAdmission],
    of device: USBTransportDevice,
    binding: ProtocolBinding,
    provider: any USBTransportProvider,
    generation: UInt64
  ) async -> USBDeviceHandlingOutcome {
    let productName = controllerDisplayName(
      productName: device.productName,
      vendorID: device.vendorID,
      productID: device.productID
    )
    var started: [(identifier: DeviceIdentifier, pipeline: DevicePipeline)] = []
    for role in roles {
      // Starting an earlier role suspends the actor; the key may be taken meanwhile.
      guard isCurrentUSBDetection(generation),
        !hasUSBPipelineConflict(for: role.identifier, service: device.serviceIdentity)
      else { return await discardUSBRoles(started, of: device) }
      guard
        case .success(let driver) = protocolDriverRegistry.makeDriver(
          for: binding,
          identifier: role.identifier,
          claimed: role.resolution,
          slotOrdinal: role.slotOrdinal
        )
      else { return await discardUSBRoles(started, of: device) }
      deviceInfos[role.identifier] = DeviceInfo(
        name: productName,
        connection: "USB",
        serialNumber: role.identifier.controllerIdentity.serialNumber,
        discoverySource: .rawUSB(route: device.route),
        binding: binding,
        physicalDevice: role.resolution.physicalDevice,
        usbTransportDevice: device
      )
      print("[DeviceManager] USB device added: \(productName) (\(role.identifier))")
      let startupIndicator =
        driver.sessionPlan.assignsStartupPlayerIndicator
        ? claimStartupPlayerSlot(for: role.identifier) : nil
      let pipeline = DevicePipeline(
        identifier: role.identifier,
        transport: .usb(device: device),
        driver: driver,
        dispatcher: dispatcher,
        binding: binding,
        interface: role.resolution.physicalDevice?.interfaces?.first,
        usbStartupPlayerIndicator: startupIndicator,
        usbTransportProvider: provider,
        transportProfile: role.resolution.profile,
        externalOutputAllowed: externalOutputAllowed,
        sessionState: suspendedControllerIdentities.contains(role.identifier) ? .suspended : .active
      )
      pipelines[role.identifier] = pipeline
      started.append((role.identifier, pipeline))
      notifyControllerInventoryChanged()
      await pipeline.start()
      guard isCurrentUSBDetection(generation),
        started.allSatisfy({
          pipelines[$0.identifier] === $0.pipeline && isRunningUSBRole($0.identifier, of: device)
        })
      else { return await discardUSBRoles(started, of: device) }
    }
    await reconcileUnboundHIDClaims()
    return .claimed(started.map(\.identifier))
  }

  /// Removes one raw-USB role from the inventory and returns its pipeline for the caller to stop.
  /// Detach and admission rollback share it, so both clear the role's output state alike.
  func removeUSBRole(_ identifier: DeviceIdentifier) -> DevicePipeline? {
    let pipeline = pipelines.removeValue(forKey: identifier)
    startupPlayerSlots.removeValue(forKey: identifier)
    retireOutputQueue(for: identifier)
    discardPhysicalOutputs(for: identifier)
    deviceInfos.removeValue(forKey: identifier)
    lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
    return pipeline
  }

  /// Stops the started roles of an admission that must be retried, removing those still owned.
  /// Every started pipeline is stopped; a pipeline already stopped elsewhere ignores it.
  private func discardUSBRoles(
    _ started: [(identifier: DeviceIdentifier, pipeline: DevicePipeline)],
    of device: USBTransportDevice
  ) async -> USBDeviceHandlingOutcome {
    guard !started.isEmpty else { return .retry }
    let owned = started.filter {
      pipelines[$0.identifier] === $0.pipeline && isRunningUSBRole($0.identifier, of: device)
    }
    for role in owned { _ = removeUSBRole(role.identifier) }
    if !owned.isEmpty { notifyControllerInventoryChanged() }
    for (_, pipeline) in started { await pipeline.stop() }
    await reconcileUnboundHIDClaims()
    return .retry
  }
}
