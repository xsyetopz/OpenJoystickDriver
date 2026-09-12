import Foundation

extension DeviceManager {
  // MARK: - HID detection (class 0x03)

  func ensureHIDDetectionState(for state: PermissionManager.AccessState) async {
    switch state {
    case .granted:
      guard hidDetectionTask == nil else { return }
      hidDetectionTask = Task { await self.runHIDDetection() }
    case .unknown, .denied:
      hidDetectionTask?.cancel()
      hidDetectionTask = nil
      await removeHIDPipelines()
    }
  }

  private func runHIDDetection() async {
    print("[DeviceManager] HID detection started" + " (class 0x03)")
    let events = await hidManager.deviceEvents()
    for await event in events { await handleHIDEvent(event) }
  }

  /// Handles backend events in their delivered order, including ownership before input.
  func handleHIDEvent(_ event: HIDDeviceEvent) async {
    switch event {
    case .connected(
      let vid,
      let pid,
      let serial,
      let loc,
      let productName,
      let transport,
      let ownership
    ):
      await handleHIDDeviceConnected(
        vendorID: vid,
        productID: pid,
        serialNumber: serial,
        locationID: loc,
        productName: productName,
        transport: transport,
        ownership: ownership
      )
    case .ownershipChanged(let locationID, let ownership):
      await updateHIDOwnership(ownership, locationID: locationID)
    case .disconnected(let vid, let pid, let loc):
      await handleHIDDeviceDisconnected(vendorID: vid, productID: pid, locationID: loc)
    case .inputReport(let loc, _, let data): await routeHIDInputReport(locationID: loc, data: data)
    case .inputValue(let loc, let value): await routeHIDElementValue(locationID: loc, value: value)
    }
  }

  private func updateHIDOwnership(_ ownership: HIDInputOwnership, locationID: UInt32) async {
    let identifiers = deviceInfos.keys.filter { $0.locationID == locationID }
    for identifier in identifiers {
      guard let info = deviceInfos[identifier], case .hid = info.discoverySource else { continue }
      deviceInfos[identifier]?.hidInputOwnership = ownership
      if ownership == .ownedByAnotherClient, info.hidInputOwnership != .ownedByAnotherClient {
        if let pipeline = pipelines[identifier] {
          await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
          await pipeline.stop()
        }
      } else if ownership != .ownedByAnotherClient, info.hidInputOwnership == .ownedByAnotherClient
      {
        // A fresh parser and normalized state prevent replaying controls held before access loss.
        pipelines.removeValue(forKey: identifier)
        await handleHIDDeviceConnected(
          vendorID: identifier.vendorID,
          productID: identifier.productID,
          serialNumber: identifier.serialNumber,
          locationID: locationID,
          productName: info.name,
          transport: info.connection,
          ownership: ownership
        )
        continue
      }
      if let listener = dispatcher as? any ControllerInputOwnershipListener {
        await listener.controllerInputOwnershipChanged(ownership, for: identifier)
      }
    }
  }

  private func removeHIDPipelines() async {
    let hidIdentifiers = pipelines.keys.filter {
      deviceInfos[$0]?.discoverySource.requiresInputMonitoring == true
    }

    for identifier in hidIdentifiers {
      guard let pipeline = pipelines.removeValue(forKey: identifier) else { continue }
      await neutralizePhysicalOutputs(for: identifier, pipeline: pipeline)
      deviceInfos.removeValue(forKey: identifier)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
      await pipeline.stop()
      print("[DeviceManager] HID pipeline removed: \(identifier)")
    }
  }

  private func handleHIDDeviceConnected(
    vendorID: UInt16,
    productID: UInt16,
    serialNumber: String?,
    locationID: UInt32,
    productName: String?,
    transport: String?,
    ownership: HIDInputOwnership
  ) async {
    let identifier = DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serialNumber,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else {
      await updateHIDOwnership(ownership, locationID: locationID)
      return
    }
    if let existingIdentifier = Self.matchingPhysicalIdentifier(
      for: identifier,
      among: pipelines.keys
    ) {
      guard case .rawUSB = deviceInfos[existingIdentifier]?.discoverySource else { return }
      let replacedPipeline = pipelines.removeValue(forKey: existingIdentifier)
      if let replacedPipeline {
        await neutralizePhysicalOutputs(for: existingIdentifier, pipeline: replacedPipeline)
      }
      deviceInfos.removeValue(forKey: existingIdentifier)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: existingIdentifier)
      Task { await replacedPipeline?.stop() }
      print("[DeviceManager] Replacing duplicate raw USB pipeline with HID: \(identifier)")
    }

    let name = controllerDisplayName(
      productName: productName,
      vendorID: vendorID,
      productID: productID
    )
    let connection = transport ?? "HID"
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: connection,
      serialNumber: serialNumber,
      discoverySource: .hid,
      hidInputOwnership: ownership
    )
    await updateHIDOwnership(ownership, locationID: locationID)
    guard deviceInfos[identifier] != nil, pipelines[identifier] == nil else { return }
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser: any InputParser
    if parserRegistry.parserName(for: identifier) == "DS4", connection == "Bluetooth" {
      parser = DS4Parser(prefersBluetooth: true)
    } else if parserRegistry.parserName(for: identifier) == "DualSense" {
      let profile = parserRegistry.runtimeProfile(for: identifier)
      parser = DualSenseParser(
        prefersBluetooth: connection == "Bluetooth",
        hasEdgeButtons: profile.quirks.contains("edgeButtons")
      )
    } else {
      parser = parserRegistry.parser(for: identifier)
    }
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: locationID),
      parser: parser,
      dispatcher: dispatcher,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    guard ownership != .ownedByAnotherClient else { return }
    await pipeline.start()
    guard pipelines[identifier] === pipeline else { return }
    if !pipeline.requiresInputConnectionBeforeOutput() {
      await dispatcher.dispatch(events: [], from: identifier)
    }
    await sendHIDStartupFeatureReadRequestsIfNeeded(
      pipeline: pipeline,
      parser: parser,
      locationID: locationID,
      transport: transport
    )
    if !pipeline.requiresInputConnectionBeforeOutput() {
      await sendHIDStartupFeatureReportsIfNeeded(
        parser: parser,
        locationID: locationID,
        transport: transport
      )
    }
    await sendHIDStartupOutputReportsIfNeeded(
      pipeline: pipeline,
      locationID: locationID,
      transport: transport
    )
    await requestHIDInputConnectionStatusIfNeeded(parser: parser, locationID: locationID)
  }

  private func sendHIDStartupFeatureReadRequestsIfNeeded(
    pipeline: DevicePipeline,
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) async {
    guard let provider = parser as? any HIDStartupFeatureReadRequestProvider else { return }
    for request in provider.hidStartupFeatureReadRequests(transport: transport) {
      let outcome = await HIDFeatureReadRetry.run(
        maximumAttempts: parser is any HIDFeatureReportConsumer ? 3 : 1
      ) {
        await self.attemptHIDStartupFeatureRead(
          pipeline: pipeline, request: request, locationID: locationID, transport: transport
        )
      }
      switch outcome {
      case .accepted: break
      case .stopped: return
      case .retry:
        print("[DeviceManager] HID startup feature read exhausted for loc=\(locationID)")
      }
    }
  }

  private func attemptHIDStartupFeatureRead(
    pipeline: DevicePipeline,
    request: PhysicalHIDFeatureReadRequest,
    locationID: UInt32,
    transport: String?
  ) async -> HIDFeatureReadAttempt {
    guard await isCurrentHIDStartupPipeline(pipeline) else { return .stopped }
    let data = await hidManager.getFeatureReport(locationID: locationID, request: request)
    guard await isCurrentHIDStartupPipeline(pipeline) else { return .stopped }
    guard let data else { return .retry }
    guard pipeline.parser is any HIDFeatureReportConsumer else { return .accepted }
    let accepted = await pipeline.consumeHIDFeatureReport(
      data, request: request, transport: transport
    )
    return accepted ? .accepted : .retry
  }

  private func sendHIDStartupFeatureReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) async {
    guard let provider = parser as? any HIDStartupFeatureReportProvider else { return }
    for report in provider.hidStartupFeatureReports(transport: transport) {
      let sent = await hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent { print("[DeviceManager] HID startup feature report failed for loc=\(locationID)") }
    }
  }

  private func sendHIDStartupOutputReportsIfNeeded(
    pipeline: DevicePipeline,
    locationID: UInt32,
    transport: String?
  ) async {
    guard await isCurrentHIDStartupPipeline(pipeline) else { return }
    let (reports, interval) = await pipeline.hidStartupOutputPlan(transport: transport)
    if interval == 0 {
      for report in reports {
        guard await isCurrentHIDStartupPipeline(pipeline) else { return }
        let sent = await hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
      scheduleHIDStartupRecovery(pipeline: pipeline, locationID: locationID, interval: interval)
      return
    }
    Task {
      for (index, report) in reports.enumerated() {
        if index > 0 {
          do { try await Task.sleep(nanoseconds: interval) } catch { return }
        }
        guard !Task.isCancelled, await isCurrentHIDStartupPipeline(pipeline) else { return }
        let sent = await hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
      scheduleHIDStartupRecovery(pipeline: pipeline, locationID: locationID, interval: interval)
    }
  }

  private func scheduleHIDStartupRecovery(
    pipeline: DevicePipeline, locationID: UInt32, interval: UInt64
  ) {
    guard pipeline.parser is any HIDStartupRecoveryProvider else { return }
    Task {
      for round in 0..<3 {
        do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
        guard !Task.isCancelled, await isCurrentHIDStartupPipeline(pipeline) else { return }
        if round == 2 {
          await pipeline.expireHIDStartupRequests()
          return
        }
        let reports = await pipeline.pendingHIDStartupReports()
        for (index, report) in reports.enumerated() {
          if index > 0 {
            do { try await Task.sleep(nanoseconds: interval) } catch { return }
          }
          guard !Task.isCancelled, await isCurrentHIDStartupPipeline(pipeline) else { return }
          _ = await hidManager.setOutputReport(locationID: locationID, report: report)
        }
      }
    }
  }

  func isCurrentHIDStartupPipeline(_ pipeline: DevicePipeline) async -> Bool {
    guard await pipeline.isActive else { return false }
    // Recheck identity after the actor hop: a reconnect may reuse the same location and IDs.
    return pipelines[pipeline.identifier] === pipeline
      && deviceInfos[pipeline.identifier]?.hidInputOwnership != .ownedByAnotherClient
  }

  private func requestHIDInputConnectionStatusIfNeeded(parser: any InputParser, locationID: UInt32)
    async
  {
    guard let requester = parser as? any HIDInputConnectionStatusRequester,
      let report = requester.inputConnectionStatusRequestReport()
    else { return }
    let sent = await hidManager.setFeatureReport(locationID: locationID, report: report)
    if !sent {
      print("[DeviceManager] HID input connection status request failed for loc=\(locationID)")
    }
  }

  private func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
    async
  {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      let pipeline = pipelines.removeValue(forKey: key)
      if let pipeline { await neutralizePhysicalOutputs(for: key, pipeline: pipeline) }
      deviceInfos.removeValue(forKey: key)
      lastPhysicalHIDOutputNanoseconds.removeValue(forKey: key)
      await sendHIDShutdownFeatureReportsIfNeeded(pipeline: pipeline, locationID: locationID)
      await pipeline?.stop()
      print(
        "[DeviceManager] HID device disconnected:" + " VID=\(vendorID) PID=\(productID)"
          + " loc=\(locationID)"
      )
    }
  }

  func sendHIDShutdownFeatureReportsIfNeeded(pipeline: DevicePipeline?, locationID: UInt32) async {
    guard let pipeline else { return }
    for report in await pipeline.hidShutdownFeatureReports() {
      let sent = await hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent { print("[DeviceManager] HID shutdown feature report failed for loc=\(locationID)") }
    }
  }

  private func routeHIDElementValue(locationID: UInt32, value: HIDElementValue) async {
    guard let key = pipelines.keys.first(where: { $0.locationID == locationID }),
      let pipeline = pipelines[key]
    else { return }
    await pipeline.feedHIDElementValue(value)
  }

  private func routeHIDInputReport(locationID: UInt32, data: Data) async {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }),
      let featureReports = await pipelines[key]?.feedHIDData(data)
    {
      for report in featureReports {
        let sent = await hidManager.setFeatureReport(locationID: locationID, report: report)
        if !sent {
          print("[DeviceManager] HID lifecycle feature report failed for loc=\(locationID)")
        }
      }
    }
  }
}
