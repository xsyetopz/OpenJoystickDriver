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
    for await event in hidManager.deviceEvents() {
      switch event {
      case .connected(let vid, let pid, let serial, let loc, let productName, let transport):
        handleHIDDeviceConnected(
          vendorID: vid,
          productID: pid,
          serialNumber: serial,
          locationID: loc,
          productName: productName,
          transport: transport
        )
      case .disconnected(let vid, let pid, let loc):
        await handleHIDDeviceDisconnected(vendorID: vid, productID: pid, locationID: loc)
      case .inputReport(let loc, _, let data):
        await routeHIDInputReport(locationID: loc, data: data)
      case .inputValue(let loc, let value):
        await routeHIDElementValue(locationID: loc, value: value)
      }
    }
  }

  private func removeHIDPipelines() async {
    let hidIdentifiers = pipelines.keys.filter { (deviceInfos[$0]?.connection ?? "") != "USB" }

    for identifier in hidIdentifiers {
      guard let pipeline = pipelines.removeValue(forKey: identifier) else { continue }
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
    transport: String?
  ) {
    let identifier = DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: serialNumber,
      locationID: locationID
    )

    guard pipelines[identifier] == nil else { return }
    if let existingIdentifier = Self.matchingPhysicalIdentifier(
      for: identifier,
      among: pipelines.keys
    ) {
      guard deviceInfos[existingIdentifier]?.discoverySource == .rawUSB else { return }
      let replacedPipeline = pipelines.removeValue(forKey: existingIdentifier)
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
      discoverySource: .hid
    )
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser: any InputParser
    if parserRegistry.parserName(for: identifier) == "DS4", connection == "Bluetooth" {
      parser = DS4Parser(prefersBluetooth: true)
    } else if parserRegistry.parserName(for: identifier) == "DualSense" {
      parser = DualSenseParser(prefersBluetooth: connection == "Bluetooth")
    } else {
      parser = parserRegistry.parser(for: identifier)
    }
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .hid(locationID: locationID),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: nil,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    if !pipeline.requiresInputConnectionBeforeOutput() {
      Task { await dispatcher.dispatch(events: [], from: identifier) }
    }
    sendHIDStartupFeatureReadRequestsIfNeeded(
      parser: parser,
      locationID: locationID,
      transport: transport
    )
    if !pipeline.requiresInputConnectionBeforeOutput() {
      sendHIDStartupFeatureReportsIfNeeded(
        parser: parser,
        locationID: locationID,
        transport: transport
      )
    }
    sendHIDStartupOutputReportsIfNeeded(
      parser: parser,
      locationID: locationID,
      transport: transport
    )
    requestHIDInputConnectionStatusIfNeeded(parser: parser, locationID: locationID)
  }

  private func sendHIDStartupFeatureReadRequestsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReadRequestProvider else { return }
    for request in provider.hidStartupFeatureReadRequests(transport: transport)
    where hidManager.getFeatureReport(locationID: locationID, request: request) == nil {
      print("[DeviceManager] HID startup feature report read failed for loc=\(locationID)")
    }
  }

  private func sendHIDStartupFeatureReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReportProvider else { return }
    for report in provider.hidStartupFeatureReports(transport: transport) {
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent { print("[DeviceManager] HID startup feature report failed for loc=\(locationID)") }
    }
  }

  private func sendHIDStartupOutputReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupOutputReportProvider else { return }
    let reports = provider.hidStartupReports(transport: transport)
    let interval = provider.hidStartupReportIntervalNanoseconds(transport: transport)
    if interval == 0 {
      for report in reports {
        let sent = hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
      return
    }
    Task { [hidManager] in
      for (index, report) in reports.enumerated() {
        if index > 0 { try? await Task.sleep(nanoseconds: interval) }
        let sent = hidManager.setOutputReport(locationID: locationID, report: report)
        if !sent { print("[DeviceManager] HID startup output report failed for loc=\(locationID)") }
      }
    }
  }

  private func requestHIDInputConnectionStatusIfNeeded(parser: any InputParser, locationID: UInt32)
  {
    guard let requester = parser as? any HIDInputConnectionStatusRequester,
      let report = requester.inputConnectionStatusRequestReport()
    else { return }
    let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
    if !sent {
      print("[DeviceManager] HID input connection status request failed for loc=\(locationID)")
    }
  }

  private func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
    async
  {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      let pipeline = pipelines.removeValue(forKey: key)
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
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
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
        let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
        if !sent {
          print("[DeviceManager] HID lifecycle feature report failed for loc=\(locationID)")
        }
      }
    }
  }
}
