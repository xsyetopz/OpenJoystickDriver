import CoreHID
import Foundation

@available(macOS 15, *) actor CoreHIDAccessBackend: HIDAccessBackend {
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
  private var recordsByDeviceID: [UInt64: ClientRecord] = [:]
  private var deviceIDsByLocation: [UInt32: Set<UInt64>] = [:]
  private let eventAdapter = SynchronizedPhysicalHIDBackendEventAdapter()

  init(virtualProfile _: VirtualDeviceProfile, additionalProfileIdentifiers: [DeviceIdentifier]) {
    var criteria = [
      HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.gamepad)),
      HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.joystick)),
      HIDDeviceManager.DeviceMatchingCriteria(primaryUsage: .genericDesktop(.multiAxisController))
    ]
    criteria += additionalProfileIdentifiers.map {
      HIDDeviceManager.DeviceMatchingCriteria(
        vendorID: UInt32($0.vendorID),
        productID: UInt32($0.productID)
      )
    }
    matchingCriteria = criteria
  }

  func deviceEvents() -> AsyncStream<HIDDeviceEvent> {
    managerTask?.cancel()
    return AsyncStream { continuation in
      continuation.onTermination = { [weak self] _ in Task { await self?.stop() } }
      managerTask = Task { [weak self] in await self?.monitorManager(continuation: continuation) }
    }
  }

  func setOutputReport(locationID: UInt32, report: PhysicalHIDOutputReport) async -> Bool {
    await setReport(locationID: locationID, report: report, type: .output)
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
          id: HIDReportID(rawValue: request.reportID)
        )
        return Data(data.prefix(request.length))
      } catch { continue }
    }
    return nil
  }

  private func setReport(locationID: UInt32, report: PhysicalHIDOutputReport, type: HIDReportType)
    async -> Bool
  {
    guard eventAdapter.acceptsFeedback(locationID: locationID) else { return false }
    for client in clients(at: locationID) {
      do {
        try await client.dispatchSetReportRequest(
          type: type,
          id: HIDReportID(rawValue: report.reportID),
          data: Data(report.bytes)
        )
        return true
      } catch { continue }
    }
    return false
  }

  private func clients(at locationID: UInt32) -> [HIDDeviceClient] {
    (deviceIDsByLocation[locationID] ?? []).compactMap { recordsByDeviceID[$0]?.client }
  }

  private func monitorManager(continuation: AsyncStream<HIDDeviceEvent>.Continuation) async {
    let notifications = await manager.monitorNotifications(matchingCriteria: matchingCriteria)
    do {
      for try await notification in notifications {
        if Task.isCancelled { break }
        switch notification {
        case .deviceMatched(let reference):
          await add(reference: reference, continuation: continuation)
        case .deviceRemoved(let reference): remove(reference: reference, continuation: continuation)
        @unknown default: break
        }
      }
    } catch { print("[CoreHIDAccessBackend] Device monitoring failed: \(error)") }
    continuation.finish()
  }

  private func add(
    reference: HIDDeviceClient.DeviceReference,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation
  ) async {
    guard recordsByDeviceID[reference.deviceID] == nil,
      let client = HIDDeviceClient(deviceReference: reference)
    else { return }

    let vendorID = UInt16(truncatingIfNeeded: await client.vendorID)
    let productID = UInt16(truncatingIfNeeded: await client.productID)
    let serialNumber = await client.serialNumber
    let productName = await client.product
    let locationID = UInt32(truncatingIfNeeded: await client.locationID ?? reference.deviceID)
    let syntheticProperty = await client["kIOHIDGCSyntheticDeviceKey"]?.unsafeObject
    let transport = Self.transportName(await client.transport)
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

    do { try await client.seizeDevice() } catch {
      print("[CoreHIDAccessBackend] Non-exclusive access for \(vendorID):\(productID): \(error)")
    }

    let task = Task { [weak self] in
      guard let self else { return }
      await self.monitor(
        client: client,
        deviceID: reference.deviceID,
        locationID: locationID,
        continuation: continuation
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
        transport: transport
      )
    )
  }

  private func monitor(
    client: HIDDeviceClient,
    deviceID: UInt64,
    locationID: UInt32,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation
  ) async {
    guard eventAdapter.acceptsInput(deviceID: deviceID) else { return }
    let inputElements = await client.elements.filter { $0.type == .input }
    let notifications = await client.monitorNotifications(
      reportIDsToMonitor: [HIDReportID.allReports],
      elementsToMonitor: inputElements
    )
    do {
      for try await notification in notifications {
        if Task.isCancelled { break }
        switch notification {
        case .inputReport(let reportID, let data, _):
          var bytes = [UInt8](data)
          if let reportID, bytes.first != reportID.rawValue {
            bytes.insert(reportID.rawValue, at: 0)
          }
          continuation.yield(
            .inputReport(
              locationID: locationID,
              reportID: reportID?.rawValue ?? 0,
              data: Data(bytes)
            )
          )
        case .elementUpdates(let values):
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
                  integerValue: value.integerValue(asTypeTruncatingIfNeeded: Int.self)
                )
              )
            )
          }
        case .deviceRemoved: return
        case .deviceSeized, .deviceUnseized: break
        @unknown default: break
        }
      }
    } catch {
      if !Task.isCancelled {
        print("[CoreHIDAccessBackend] Device notification failed at \(locationID): \(error)")
      }
    }
  }

  private func remove(
    reference: HIDDeviceClient.DeviceReference,
    continuation: AsyncStream<HIDDeviceEvent>.Continuation
  ) {
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
    if removal.shouldCancelNotification { record.notificationTask.cancel() }
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
    }
  }

  private func stop() {
    managerTask?.cancel()
    managerTask = nil
    recordsByDeviceID.values.forEach { $0.notificationTask.cancel() }
    recordsByDeviceID.removeAll()
    deviceIDsByLocation.removeAll()
    eventAdapter.reset()
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
