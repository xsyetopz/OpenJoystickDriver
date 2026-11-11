import Foundation
import IOKit

@testable import OpenJoystickDriverKit

/// A catalogued Xbox 360 receiver (045E:0719) with a synthetic 8-interface configuration
/// descriptor: receiver slot triple FF/5D/81 on 0/2/4/6 and another vendor triple on 1/3/5/7. The
/// layout is synthetic; slot interface numbers on macOS have not been captured. Each opened
/// interface gets its own scripted session, and a reopen gets its `reopened` session.
///
/// Opens model the host: an interface exists only once the device is configured (the IOUSBHost
/// provider waits for its service), and SET_CONFIGURATION, sent when
/// ``USBTransportOpenOptions/setsConfiguration(current:)`` says so, terminates every other open
/// interface.
actor ReceiverSlotProvider: USBTransportProvider {
  static let device = USBTransportDevice(
    route: .rawUSB,
    serviceID: 70,
    vendorID: 0x045E,
    productID: 0x0719,
    locationID: 71
  )
  static let slotInterfaces: [UInt8] = [0, 2, 4, 6]

  private var listedDevices: [USBTransportDevice] = [device]
  private let isConfigured: Bool
  let sessions: [UInt8: RecoveryUSBSession]
  let reopened: [UInt8: RecoveryUSBSession]
  private(set) var openedOptions: [USBTransportOpenOptions] = []
  /// Interfaces whose open sent SET_CONFIGURATION, in order.
  private(set) var configuringInterfaces: [UInt8] = []
  /// Open interfaces a SET_CONFIGURATION terminated.
  private(set) var terminatedInterfaces: [UInt8] = []
  private var currentConfiguration: UInt8? {
    didSet {
      guard currentConfiguration != nil else { return }
      let waiting = configurationWaiters
      configurationWaiters.removeAll()
      for waiter in waiting { waiter.finish() }
    }
  }
  /// Opens waiting for the device to be configured, resumed when a configuration is set.
  private var configurationWaiters: [AsyncStream<Void>.Continuation] = []
  private var openInterfaces: Set<UInt8> = []

  /// `sessions` maps an interface number to the session its first open returns.
  init(
    sessions: [UInt8: RecoveryUSBSession],
    reopened: [UInt8: RecoveryUSBSession] = [:],
    isConfigured: Bool = true
  ) {
    self.sessions = sessions
    self.reopened = reopened
    self.isConfigured = isConfigured
    currentConfiguration = isConfigured ? 1 : nil
  }

  static func identifier(interface: UInt8) -> LogicalControllerID {
    LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      locationID: device.locationID,
      interfaceNumber: interface
    )
  }

  func devices() -> [USBTransportDevice] { listedDevices }

  func setDevices(_ devices: [USBTransportDevice]) { listedDevices = devices }

  func physicalDeviceObservation(for _: USBTransportDevice) -> PhysicalDevice? { passive }

  func resolveTransport(
    for _: USBTransportDevice,
    configured profile: DeviceTransportProfile
  ) -> USBTransportResolution { USBTransportResolution(profile: profile, physicalDevice: passive) }

  func configurationObservation(
    for _: USBTransportDevice,
    configurationValue _: UInt8
  ) -> PhysicalDevice? { Self.descriptor }

  func open(
    _: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    let interface = options.interfaceNumber
    let isReopen = openedOptions.contains { $0.interfaceNumber == interface }
    openedOptions.append(options)
    if options.setsConfiguration(current: currentConfiguration) {
      configuringInterfaces.append(interface)
      currentConfiguration = options.configurationValue
      terminatedInterfaces += openInterfaces.subtracting([interface]).sorted()
      openInterfaces.removeAll()
    }
    try await waitUntilConfigured()
    guard let session = isReopen ? reopened[interface] : sessions[interface] else {
      throw USBTransportError.notFound
    }
    openInterfaces.insert(interface)
    return session
  }

  private func waitUntilConfigured() async throws {
    guard currentConfiguration == nil else { return }
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    configurationWaiters.append(continuation)
    for await _ in stream {}
    try Task.checkCancellation()
  }

  /// Registry facts before configuration carry no interfaces; after it, the descriptor's.
  private var passive: PhysicalDevice {
    isConfigured
      ? Self.descriptor
      : PhysicalDevice(
        serviceAddress: Self.device.serviceAddress,
        vendorID: Self.device.vendorID,
        productID: Self.device.productID,
        deviceClass: 0xFF
      )
  }

  private static let descriptor = PhysicalDevice(
    serviceAddress: device.serviceAddress,
    vendorID: device.vendorID,
    productID: device.productID,
    deviceClass: 0xFF,
    configurationValue: 1,
    interfaces: (0..<8).map(ReceiverRoleProfileTests.syntheticInterface)
  )
}
