import Foundation

/// Serves IOHID devices and Switch 2 Bluetooth LE controllers as one HID backend, routing each call
/// by the address of its connection.
final class BluetoothLECompositeHIDBackend: HIDAccessBackend {
  /// The backend that serves every device except the Switch 2 Bluetooth LE controllers.
  private let primary: any HIDAccessBackend
  /// The hub that serves the Switch 2 Bluetooth LE controllers.
  private let hub: Switch2BluetoothLEHub

  /// Creates a backend from the primary backend and the hub.
  init(primary: any HIDAccessBackend, hub: Switch2BluetoothLEHub) {
    self.primary = primary
    self.hub = hub
  }

  /// Merges both event streams.
  ///
  /// The merged stream ends when the IOHID stream ends, so an IOHID access failure still ends
  /// detection.
  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> {
    let primaryEvents = await primary.deviceEvents()
    let hubEvents = hub.events()
    let (merged, continuation) = AsyncStream.makeStream(of: HIDDeviceEvent.self)
    let primaryTask = Task {
      for await event in primaryEvents { continuation.yield(event) }
      continuation.finish()
    }
    let hubTask = Task { for await event in hubEvents { continuation.yield(event) } }
    continuation.onTermination = { _ in
      primaryTask.cancel()
      hubTask.cancel()
    }
    return merged
  }

  /// The connections of the primary backend and of the hub; nil when the primary backend cannot
  /// list them.
  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    guard let primarySnapshots = await primary.currentConnectionSnapshots() else { return nil }
    return primarySnapshots + hub.connectionSnapshots()
  }

  /// Sends the output report to the hub or to the primary backend, by the address.
  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(address), case .gattPeripheral(let peripheralID) = address else {
      return await primary.setOutputReport(address: address, report: report)
    }
    return hub.setOutputReport(peripheralID: peripheralID, report: report)
  }

  /// Sends the output report to the hub or to the primary backend, by the connection's address.
  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(connection.routingAddress),
      case .gattPeripheral(let peripheralID) = connection.routingAddress
    else {
      return await primary.setOutputReport(connection: connection, report: report)
    }
    return hub.setOutputReport(peripheralID: peripheralID, report: report)
  }

  /// Sets a feature report on the primary backend; a hub link has no feature reports.
  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(address) else {
      return await primary.setFeatureReport(address: address, report: report)
    }
    return .unavailable
  }

  /// Sets a feature report on the primary backend; a hub link has no feature reports.
  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.setFeatureReport(connection: connection, report: report)
    }
    return .unavailable
  }

  /// Reads a feature report from the primary backend; a hub link has no feature reports.
  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(address) else {
      return await primary.getFeatureReport(address: address, request: request)
    }
    return .unavailable
  }

  /// Reads a feature report from the primary backend; a hub link has no feature reports.
  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.getFeatureReport(connection: connection, request: request)
    }
    return .unavailable
  }

  /// Probes a feature report on the primary backend; a hub link has no feature reports.
  func probeFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    guard hub.owns(connection.routingAddress) else {
      return await primary.probeFeatureReport(connection: connection, request: request)
    }
    return .unavailable
  }

  // macOS has no HID client for a GATT link, so OJD always owns its input.
  /// Releases the input claim at the primary backend; a hub link is always released.
  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else {
      return await primary.releaseInputClaim(address: address)
    }
    return .released
  }

  /// Reacquires the input claim at the primary backend; a hub link is always reacquired.
  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else {
      return await primary.reacquireInputClaim(address: address)
    }
    return .reacquired
  }

  /// Closes the device handles at the primary backend; a hub link holds no IOHID handle.
  func closeDeviceHandles(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else { return await primary.closeDeviceHandles(address: address) }
    return .unavailable
  }

  /// Opens the device handles again at the primary backend; a hub link holds no IOHID handle.
  func reopenDeviceHandles(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    guard hub.owns(address) else { return await primary.reopenDeviceHandles(address: address) }
    return .unavailable
  }

  /// Retries the input claim at the primary backend; a hub link needs none.
  func retryInputClaim(address: ControllerConnectionAddress) async {
    guard !hub.owns(address) else { return }
    await primary.retryInputClaim(address: address)
  }

  /// Routes the element values at the primary backend; a hub link has none.
  func routeElementValues(connection: HIDDeviceConnection) async {
    guard !hub.owns(connection.routingAddress) else { return }
    await primary.routeElementValues(connection: connection)
  }

  /// Switch 2 Bluetooth LE controllers are never native gamepads, so only IOHID devices change.
  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    await primary.reevaluateOwnership(of: models)
  }
}

/// Opens a Switch 2 Bluetooth LE controller's command channel over GATT, and every other device
/// through the USB provider.
final class BluetoothLECompositeUSBTransportProvider: USBTransportProvider {
  /// The provider for every device except the Switch 2 Bluetooth LE controllers; nil when there is
  /// none.
  private let base: (any USBTransportProvider)?
  /// The hub that serves the Switch 2 Bluetooth LE controllers.
  private let hub: Switch2BluetoothLEHub

  /// Creates a provider from the base provider and the hub.
  init(base: (any USBTransportProvider)?, hub: Switch2BluetoothLEHub) {
    self.base = base
    self.hub = hub
  }

  /// The devices of the base provider; none without one.
  func devices() async throws -> [USBTransportDevice] { try await base?.devices() ?? [] }

  /// Opens `device` through the base provider.
  ///
  /// - Throws: ``USBTransportError/notFound`` without a base provider, or the error of the base
  ///   provider.
  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard let base else { throw USBTransportError.notFound }
    return try await base.open(device, options: options)
  }

  /// Opens the command channel at `address`: over GATT for a controller of the hub, else through
  /// the base provider.
  ///
  /// - Throws: ``USBTransportError/notFound`` without a base provider, or the error of opening the
  ///   channel.
  func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    if case .gattPeripheral(let peripheralID) = address, hub.owns(address) {
      return Switch2BluetoothLECommandSession(hub: hub, peripheralID: peripheralID)
    }
    guard let base else { throw USBTransportError.notFound }
    return try await base.openCommandChannel(at: address, model: model, options: options)
  }

  /// Resolves the transport through the base provider; without one, the configured profile.
  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    guard let base else { return USBTransportResolution(profile: configured) }
    return await base.resolveTransport(for: device, configured: configured)
  }

  /// The observation of `device` by the base provider; nil without one.
  func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice? {
    await base?.physicalDeviceObservation(for: device)
  }

  /// The observation of a configuration of `device` by the base provider.
  ///
  /// - Throws: ``USBTransportError/notSupported`` without a base provider, or the error of the base
  ///   provider.
  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) async throws -> PhysicalDevice? {
    guard let base else { throw USBTransportError.notSupported }
    return try await base.configurationObservation(
      for: device,
      configurationValue: configurationValue
    )
  }

  /// Resets `device` through the base provider.
  ///
  /// - Throws: ``USBTransportError/notSupported`` without a base provider, or the error of the base
  ///   provider.
  func resetDevice(_ device: USBTransportDevice) async throws {
    guard let base else { throw USBTransportError.notSupported }
    try await base.resetDevice(device)
  }

  /// The exclusive owner of `device` according to the base provider.
  ///
  /// - Throws: ``USBTransportError/notSupported`` without a base provider, or the error of the base
  ///   provider.
  func exclusiveOwner(of device: USBTransportDevice) async throws -> String? {
    guard let base else { throw USBTransportError.notSupported }
    return try await base.exclusiveOwner(of: device)
  }

  /// Waits until the base provider reports the interface released.
  ///
  /// - Throws: ``USBTransportError/notSupported`` without a base provider, or the error of the base
  ///   provider.
  func waitForRelease(of device: USBTransportDevice, interfaceNumber: UInt8) async throws {
    guard let base else { throw USBTransportError.notSupported }
    try await base.waitForRelease(of: device, interfaceNumber: interfaceNumber)
  }
}

/// A Switch 2 command channel over GATT: OUT writes go to the command characteristic, and IN reads
/// return command-reply notifications.
final class Switch2BluetoothLECommandSession: USBTransportSession {
  /// The hub that holds the link.
  private let hub: Switch2BluetoothLEHub
  /// The peripheral's Core Bluetooth identifier.
  private let peripheralID: UUID

  /// Creates a session for the controller `peripheralID`.
  init(hub: Switch2BluetoothLEHub, peripheralID: UUID) {
    self.hub = hub
    self.peripheralID = peripheralID
  }

  /// The session owns the input exclusively.
  var inputOwnership: HIDInputOwnership { .exclusive }

  /// Writes `data` to the command characteristic.
  ///
  /// - Throws: ``USBTransportError/notSupported`` unless `endpoint` is an OUT endpoint, or the
  ///   error of the write.
  func write(endpoint: UInt8, data: [UInt8], timeout _: UInt32) throws -> Int {
    guard USBEndpointDirection(endpointAddress: endpoint) == .out else {
      throw USBTransportError.notSupported
    }
    try hub.writeCommand(peripheralID: peripheralID, bytes: data)
    return data.count
  }

  /// Reads a command reply of at most `length` bytes.
  ///
  /// - Throws: ``USBTransportError/notSupported`` unless `endpoint` is an IN endpoint and `length`
  ///   is positive, or the error of the read.
  func read(endpoint: UInt8, length: Int, timeout: UInt32) async throws -> [UInt8] {
    guard USBEndpointDirection(endpointAddress: endpoint) == .in, length > 0 else {
      throw USBTransportError.notSupported
    }
    return try await hub.readReply(
      peripheralID: peripheralID,
      length: length,
      timeoutMilliseconds: timeout
    )
  }

  /// Control transfers do not exist over GATT.
  ///
  /// - Throws: ``USBTransportError/notSupported``.
  func controlTransfer(_: USBControlTransferRequest, timeout _: UInt32) throws -> [UInt8] {
    throw USBTransportError.notSupported
  }
}
