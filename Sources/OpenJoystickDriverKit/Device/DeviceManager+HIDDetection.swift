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

  func runHIDDetection() async {
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
      }
    }
  }

  func removeHIDPipelines() async {
    let hidIdentifiers = pipelines.keys.filter {
      (deviceInfos[$0]?.connection ?? "") != "USB"
    }

    for identifier in hidIdentifiers {
      guard let pipeline = pipelines.removeValue(forKey: identifier) else { continue }
      deviceInfos.removeValue(forKey: identifier)
      await pipeline.stop()
      print("[DeviceManager] HID pipeline removed: \(identifier)")
    }
  }

  func handleHIDDeviceConnected(
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

    let name = productName ?? "Controller"
    let connection = transport ?? "HID"
    deviceInfos[identifier] = DeviceInfo(
      name: name,
      connection: connection,
      serialNumber: serialNumber
    )
    print("[DeviceManager] HID device connected:" + " \(name) (\(identifier))")
    let parser: any InputParser
    if parserRegistry.parserName(for: identifier) == "DS4", connection == "Bluetooth" {
      parser = DS4Parser(prefersBluetooth: true)
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

  func sendHIDStartupFeatureReadRequestsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReadRequestProvider else { return }
    for request in provider.hidStartupFeatureReadRequests(transport: transport)
      where hidManager.getFeatureReport(locationID: locationID, request: request) == nil
    {
      print("[DeviceManager] HID startup feature report read failed for loc=\(locationID)")
    }
  }

  func sendHIDStartupFeatureReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupFeatureReportProvider else { return }
    for report in provider.hidStartupFeatureReports(transport: transport) {
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent {
        print("[DeviceManager] HID startup feature report failed for loc=\(locationID)")
      }
    }
  }

  func sendHIDStartupOutputReportsIfNeeded(
    parser: any InputParser,
    locationID: UInt32,
    transport: String?
  ) {
    guard let provider = parser as? any HIDStartupOutputReportProvider else { return }
    for report in provider.hidStartupReports(transport: transport) {
      let sent = hidManager.setOutputReport(locationID: locationID, report: report)
      if !sent {
        print("[DeviceManager] HID startup output report failed for loc=\(locationID)")
      }
    }
  }

  func requestHIDInputConnectionStatusIfNeeded(
    parser: any InputParser,
    locationID: UInt32
  ) {
    guard let requester = parser as? any HIDInputConnectionStatusRequester,
      let report = requester.inputConnectionStatusRequestReport()
    else { return }
    let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
    if !sent {
      print("[DeviceManager] HID input connection status request failed for loc=\(locationID)")
    }
  }

  func handleHIDDeviceDisconnected(vendorID: UInt16, productID: UInt16, locationID: UInt32)
    async
  {
    if let key = pipelines.keys.first(where: { $0.locationID == locationID }) {
      let pipeline = pipelines.removeValue(forKey: key)
      deviceInfos.removeValue(forKey: key)
      await sendHIDShutdownFeatureReportsIfNeeded(pipeline: pipeline, locationID: locationID)
      await pipeline?.stop()
      print(
        "[DeviceManager] HID device disconnected:" + " VID=\(vendorID) PID=\(productID)"
          + " loc=\(locationID)"
      )
    }
  }

  func sendHIDShutdownFeatureReportsIfNeeded(
    pipeline: DevicePipeline?,
    locationID: UInt32
  ) async {
    guard let pipeline else { return }
    for report in await pipeline.hidShutdownFeatureReports() {
      let sent = hidManager.setFeatureReport(locationID: locationID, report: report)
      if !sent {
        print("[DeviceManager] HID shutdown feature report failed for loc=\(locationID)")
      }
    }
  }

  func routeHIDInputReport(locationID: UInt32, data: Data) async {
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
