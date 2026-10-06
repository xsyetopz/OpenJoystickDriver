import CoreHID
import Foundation

@available(macOS 15, *)
enum CoreHIDInputSubscriptionPlan {
  case rawReports
  case elements(any HIDElementValueParser)

  enum NotificationKind {
    case rawReport
    case elementUpdates
  }

  static func resolve(
    for identifier: DeviceIdentifier,
    registry: ParserRegistry = ParserRegistry()
  ) -> Self {
    guard
      let parser = registry.parser(for: identifier, transport: .hid) as? any HIDElementValueParser
    else { return .rawReports }
    return .elements(parser)
  }

  var monitorsRawReports: Bool {
    if case .rawReports = self { return true }
    return false
  }

  func subscribesToElement(usagePage: UInt32, usage: UInt32) -> Bool {
    switch self {
    case .rawReports: false
    case .elements(let parser): parser.acceptsElement(usagePage: usagePage, usage: usage)
    }
  }

  func forwards(_ notification: NotificationKind) -> Bool {
    switch (self, notification) {
    case (.rawReports, .rawReport), (.elements, .elementUpdates): true
    case (.rawReports, .elementUpdates), (.elements, .rawReport): false
    }
  }
}

@available(macOS 15, *)
enum CoreHIDInputReport {
  static func normalizedBytes(reportID: HIDReportID?, data: Data) -> [UInt8] {
    var bytes = [UInt8](data)
    if let reportID, bytes.first != reportID.rawValue { bytes.insert(reportID.rawValue, at: 0) }
    return bytes
  }
}

/// CoreHID returns element values sign-extended from the field's report size, so an
/// unsigned 16-bit axis (logical 0...65535) above 32767 arrives negative. Fields whose
/// logical minimum is non-negative are reinterpreted as unsigned at their report size.
enum CoreHIDElementInteger {
  static func value(signExtended raw: Int, reportSize: UInt32, logicalMinimum: Int) -> Int {
    guard raw < 0, logicalMinimum >= 0, reportSize > 0, reportSize < 64 else { return raw }
    return raw & ((1 << Int(reportSize)) - 1)
  }
}

@available(macOS 15, *)
enum CoreHIDElementReportID {
  static func value(_ reportID: HIDReportID?) -> UInt32? { reportID.map { UInt32($0.rawValue) } }
}

@available(macOS 15, *)
enum CoreHIDPhysicalReportRequest {
  static let timeout: Duration = .seconds(2)

  static func perform(_ operation: (Duration) async throws -> Void) async -> Result<Void, any Error>
  {
    do {
      try await operation(timeout)
      return .success(())
    } catch { return .failure(error) }
  }
}

@available(macOS 15, *)
actor CoreHIDAccessBackend: HIDAccessBackend {
  private struct ClientRecord {
    let client: HIDDeviceClient
    let vendorID: UInt16
    let productID: UInt16
    let locationID: UInt32
    let notificationTask: Task<Void, Never>
  }

  private let manager = HIDDeviceManager()
  private let matchingCriteria: [HIDDeviceManager.DeviceMatchingCriteria]
  private var managerTask: Task<Void, Never>?
  private var sessionID: UUID?
  private var pendingAdmissions: [UInt64: UUID] = [:]
  private var recordsByDeviceID: [UInt64: ClientRecord] = [:]
  private var deviceIDsByLocation: [UInt32: Set<UInt64>] = [:]
  private let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()

  init(virtualProfile _: VirtualDeviceProfile, additionalProfileIdentifiers: [DeviceIdentifier]) {
    var criteria = [
      AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
        primaryUsage: .genericDesktop(.gamepad)
      ),
      AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
        primaryUsage: .genericDesktop(.joystick)
      ),
      AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
        primaryUsage: .genericDesktop(.multiAxisController)
      ),
    ]
    criteria += additionalProfileIdentifiers.map {
      AppleGameControllerSyntheticHID.coreHIDMatchingCriteria(
        vendorID: UInt32($0.vendorID),
        productID: UInt32($0.productID)
      )
    }
    matchingCriteria = criteria
  }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> {
    stop()
    let sessionID = UUID()
    self.sessionID = sessionID
    return AsyncStream { continuation in
      continuation.onTermination = { [weak self] _ in
        Task { await self?.stop(sessionID: sessionID) }
      }
      managerTask = Task { [weak self] in
        await self?.monitorManager(continuation: continuation, sessionID: sessionID)
      }
    }
  }

  func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool {
    return await setReport(locationID: locationID, report: report, type: .output)
  }

  func setFeatureReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool {
    await setReport(locationID: locationID, report: report, type: .feature)
  }

  func getFeatureReport(locationID: UInt32, request: PhysicalHIDFeatureReadRequest) async -> Data? {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return nil }
    for client in clients(at: locationID) {
      do {
        let data = try await client.dispatchGetReportRequest(
          type: .feature,
          id: HIDReportID(rawValue: request.reportID),
          timeout: .seconds(2)
        )
        guard recordsByDeviceID[client.deviceReference.deviceID]?.client === client,
          eventAdapter.acceptsFeedback(locationID: locationID)
        else { continue }
        return Data(data.prefix(request.length))
      } catch { continue }
    }
    return nil
  }

  private func setReport(
    locationID: UInt32,
    report: PhysicalHIDOutputReport,
    type: HIDReportType
  ) async -> Bool {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return false }
    for client in clients(at: locationID) {
      let result = await CoreHIDPhysicalReportRequest.perform { timeout in
        try await client.dispatchSetReportRequest(
          type: type,
          id: HIDReportID(rawValue: report.reportID),
          data: Data(report.bytes),
          timeout: timeout
        )
      }
      switch result {
      case .success: return true
      case .failure(let error):
        print(
          "[CoreHIDAccessBackend] Set-report failed at \(locationID) "
            + "type=\(type) id=\(report.reportID): \(error)"
        )
      }
    }
    return false
  }

  private func clients(at locationID: UInt32) -> [HIDDeviceClient] {
    (deviceIDsByLocation[locationID] ?? []).compactMap {
      eventAdapter.acceptsInput(deviceID: $0) ? recordsByDeviceID[$0]?.client : nil
    }
  }

  private func monitorManager(
    continuation: AsyncStream<HIDDeviceEvent>.Continuation,
    sessionID: UUID
  ) async {
    let notifications = await manager.monitorNotifications(matchingCriteria: matchingCriteria)
    do {
      for try await notification in notifications {
        if Task.isCancelled || self.sessionID != sessionID { break }
        switch notification {
        case .deviceMatched(let reference):
          await add(reference: reference, continuation: continuation, sessionID: sessionID)
        case .deviceRemoved(let reference): remove(reference: reference, continuation: continuation)
        @unknown default: break
        }
      }
    } catch { print("[CoreHIDAccessBackend] Device monitoring failed: \(error)") }
    continuation.finish()
  }

  private func add(
    reference: HIDDeviceClient.DeviceReference,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation,
    sessionID: UUID
  ) async {
    guard self.sessionID == sessionID, !Task.isCancelled else { return }
    guard recordsByDeviceID[reference.deviceID] == nil, pendingAdmissions[reference.deviceID] == nil
    else { return }
    let admissionID = UUID()
    pendingAdmissions[reference.deviceID] = admissionID
    defer {
      if pendingAdmissions[reference.deviceID] == admissionID {
        pendingAdmissions.removeValue(forKey: reference.deviceID)
      }
    }
    guard !AppleGameControllerSyntheticHID.isSyntheticRegistryEntry(id: reference.deviceID) else {
      return
    }
    guard let client = HIDDeviceClient(deviceReference: reference) else { return }

    let vendorID = UInt16(truncatingIfNeeded: await client.vendorID)
    let productID = UInt16(truncatingIfNeeded: await client.productID)
    let serialNumber = await client.serialNumber
    let productName = await client.product
    let locationID = UInt32(truncatingIfNeeded: await client.locationID ?? reference.deviceID)
    let syntheticProperty = await client[AppleGameControllerSyntheticHID.propertyKey]?.unsafeObject
    let transport = Self.transportName(await client.transport)
    guard self.sessionID == sessionID, !Task.isCancelled,
      pendingAdmissions[reference.deviceID] == admissionID
    else { return }
    guard
      PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: serialNumber,
        productName: productName,
        transport: transport,
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    else { return }
    guard
      eventAdapter.add(
        deviceID: reference.deviceID,
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    else { return }

    let ownership: HIDInputOwnership
    do {
      try await client.seizeDevice()
      ownership = .exclusive
    } catch {
      ownership = Self.ownershipAfterAcquisitionFailure(error)
      print("[CoreHIDAccessBackend] Non-exclusive access for \(vendorID):\(productID): \(error)")
    }
    guard self.sessionID == sessionID, !Task.isCancelled,
      pendingAdmissions[reference.deviceID] == admissionID
    else { return }
    eventAdapter.updateOwnership(ownership, deviceID: reference.deviceID)

    let task = Task { [weak self] in
      guard let self else { return }
      await self.monitor(
        client: client,
        deviceID: reference.deviceID,
        locationID: locationID,
        continuation: continuation,
        sessionID: sessionID
      )
    }
    recordsByDeviceID[reference.deviceID] = ClientRecord(
      client: client,
      vendorID: vendorID,
      productID: productID,
      locationID: locationID,
      notificationTask: task
    )
    deviceIDsByLocation[locationID, default: []].insert(reference.deviceID)
    continuation.yield(
      .connected(
        vendorID: vendorID,
        productID: productID,
        serialNumber: serialNumber,
        locationID: locationID,
        productName: productName,
        transport: transport,
        ownership: eventAdapter.ownership(locationID: locationID)
      )
    )
  }

  private func monitor(
    client: HIDDeviceClient,
    deviceID: UInt64,
    locationID: UInt32,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation,
    sessionID: UUID
  ) async {
    let reacquire = await receiveNotifications(
      client: client,
      deviceID: deviceID,
      locationID: locationID,
      continuation: continuation,
      sessionID: sessionID
    )
    guard self.sessionID == sessionID, !Task.isCancelled,
      recordsByDeviceID[deviceID]?.client === client
    else { return }
    remove(reference: client.deviceReference, continuation: continuation, cancelNotification: false)
    if reacquire {
      // The notification stream has ended before a fresh client attempts exclusive access.
      await add(reference: client.deviceReference, continuation: continuation, sessionID: sessionID)
    }
  }

  private func receiveNotifications(
    client: HIDDeviceClient,
    deviceID: UInt64,
    locationID: UInt32,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation,
    sessionID: UUID
  ) async -> Bool {
    guard eventAdapter.isTracked(deviceID: deviceID) else { return false }
    let identifier = DeviceIdentifier(
      vendorID: UInt16(truncatingIfNeeded: await client.vendorID),
      productID: UInt16(truncatingIfNeeded: await client.productID)
    )
    let subscriptionPlan = CoreHIDInputSubscriptionPlan.resolve(for: identifier)
    let reportIDsToMonitor = subscriptionPlan.monitorsRawReports ? [HIDReportID.allReports] : []
    let elementsToMonitor = await client.elements.filter {
      $0.type == .input
        && subscriptionPlan.subscribesToElement(
          usagePage: UInt32($0.usage.page),
          usage: UInt32($0.usage.usage ?? 0)
        )
    }
    guard self.sessionID == sessionID, !Task.isCancelled else { return false }
    let notifications = await client.monitorNotifications(
      reportIDsToMonitor: reportIDsToMonitor,
      elementsToMonitor: elementsToMonitor
    )
    do {
      for try await notification in notifications {
        if Task.isCancelled || self.sessionID != sessionID { break }
        switch notification {
        case .inputReport(let reportID, let data, _):
          guard subscriptionPlan.forwards(.rawReport), eventAdapter.acceptsInput(deviceID: deviceID)
          else { continue }
          continuation.yield(
            .inputReport(
              locationID: locationID,
              reportID: reportID?.rawValue ?? 0,
              data: Data(CoreHIDInputReport.normalizedBytes(reportID: reportID, data: data))
            )
          )
        case .elementUpdates(let values):
          guard subscriptionPlan.forwards(.elementUpdates),
            eventAdapter.acceptsInput(deviceID: deviceID)
          else { continue }
          for value in values {
            let element = value.element
            continuation.yield(
              .inputValue(
                locationID: locationID,
                value: HIDElementValue(
                  usagePage: UInt32(element.usage.page),
                  usage: UInt32(element.usage.usage ?? 0),
                  logicalMinimum: Int(element.logicalMinimum ?? 0),
                  logicalMaximum: Int(element.logicalMaximum ?? 0),
                  integerValue: CoreHIDElementInteger.value(
                    signExtended: value.integerValue(asTypeTruncatingIfNeeded: Int.self),
                    reportSize: element.reportSize,
                    logicalMinimum: Int(element.logicalMinimum ?? 0)
                  ),
                  reportID: CoreHIDElementReportID.value(element.reportID)
                )
              )
            )
          }
        case .deviceRemoved: return false
        case .deviceSeized:
          eventAdapter.updateOwnership(.ownedByAnotherClient, deviceID: deviceID)
          continuation.yield(
            .ownershipChanged(
              locationID: locationID,
              ownership: eventAdapter.ownership(locationID: locationID)
            )
          )
        case .deviceUnseized: return true
        @unknown default: break
        }
      }
    } catch {
      if !Task.isCancelled {
        print("[CoreHIDAccessBackend] Device notification failed at \(locationID): \(error)")
      }
    }
    return false
  }

  private func remove(
    reference: HIDDeviceClient.DeviceReference,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation,
    cancelNotification: Bool = true
  ) {
    pendingAdmissions.removeValue(forKey: reference.deviceID)
    let removal = eventAdapter.remove(deviceID: reference.deviceID)
    guard let record = recordsByDeviceID.removeValue(forKey: reference.deviceID) else {
      for locationID in Array(deviceIDsByLocation.keys) {
        deviceIDsByLocation[locationID]?.remove(reference.deviceID)
        if deviceIDsByLocation[locationID]?.isEmpty == true {
          deviceIDsByLocation.removeValue(forKey: locationID)
        }
      }
      return
    }
    let deviceID = reference.deviceID
    if removal.shouldCancelNotification, cancelNotification { record.notificationTask.cancel() }
    deviceIDsByLocation[record.locationID]?.remove(deviceID)
    if deviceIDsByLocation[record.locationID]?.isEmpty == true {
      deviceIDsByLocation.removeValue(forKey: record.locationID)
    }
    if removal.shouldEmitDisconnect {
      continuation.yield(
        .disconnected(
          vendorID: record.vendorID,
          productID: record.productID,
          locationID: record.locationID
        )
      )
    } else if removal.wasTracked {
      continuation.yield(
        .ownershipChanged(
          locationID: record.locationID,
          ownership: eventAdapter.ownership(locationID: record.locationID)
        )
      )
    }
  }

  private func stop(sessionID: UUID? = nil) {
    if let sessionID, self.sessionID != sessionID { return }
    self.sessionID = nil
    managerTask?.cancel()
    managerTask = nil
    recordsByDeviceID.values.forEach { $0.notificationTask.cancel() }
    recordsByDeviceID.removeAll()
    pendingAdmissions.removeAll()
    deviceIDsByLocation.removeAll()
    eventAdapter.reset()
  }

  static func ownershipAfterAcquisitionFailure(_ error: any Error) -> HIDInputOwnership {
    switch error as? HIDDeviceError {
    case .exclusiveAccess: .ownedByAnotherClient
    case .notPermitted, .notPrivileged: .accessDenied
    default: .acquisitionFailed
    }
  }

  private static func transportName(_ transport: HIDDeviceTransport?) -> String? {
    guard let transport else { return nil }
    return switch transport {
    case .usb: "USB"
    case .bluetooth: "Bluetooth"
    case .bluetoothLowEnergy: "Bluetooth Low Energy"
    case .bluetoothAACP: "Bluetooth AACP"
    case .aid: "AID"
    case .i2c: "I2C"
    case .spi: "SPI"
    case .serial: "Serial"
    case .iap: "iAP"
    case .airPlay: "AirPlay"
    case .spu: "SPU"
    case .fifo: "FIFO"
    case .inductiveInBand: "Inductive In-Band"
    case .virtual: "Virtual"
    case .unknown(let value): value
    @unknown default: nil
    }
  }
}
