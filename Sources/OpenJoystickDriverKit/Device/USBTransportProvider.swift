/// Discovers and opens physical USB interfaces without exposing a transport framework to Kit.
public protocol USBTransportProvider: Sendable {
  /// Enumerates the raw USB services that this provider can see.
  func devices() async throws -> [USBTransportDevice]
  /// A count that grows each time a service ``devices()`` lists may have appeared or gone, or nil
  /// when the provider cannot observe that, so that each detection poll lists the devices.
  ///
  /// The count is read before a listing, so a change during the listing makes the next poll list
  /// again.
  var enumerationChangeCount: UInt64? { get async }
  /// Opens `device` with `options` and returns the session.
  func open(
    _ device: USBTransportDevice,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession

  /// Opens the USB command channel of the controller at `address`, which a HID-bound pipeline uses
  /// to send commands the HID interface cannot carry.
  func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession

  /// Resolves one admitted device's profile and any available physical facts without claiming the
  /// device.
  func resolveTransport(
    for device: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution

  /// Passive facts for one enumerated device before any binding exists; nil when unavailable.
  func physicalDeviceObservation(for device: USBTransportDevice) async -> PhysicalDevice?

  /// Passive facts that include the host's cached descriptor of configuration `configurationValue`,
  /// read without claiming an interface or sending SET_CONFIGURATION.
  ///
  /// Returns nil when the device reports no such configuration.
  func configurationObservation(
    for device: USBTransportDevice,
    configurationValue: UInt8
  ) async throws -> PhysicalDevice?

  /// Resets the device's USB port, which makes the host enumerate the device again as a replug
  /// does.
  ///
  /// Every open interface of the device ends, and the device returns as a new attachment.
  func resetDevice(_ device: USBTransportDevice) async throws

  /// The process or driver that holds the device for itself, as the host reports it, or nil when
  /// the host reports no exclusive owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` when the provider cannot observe owners.
  func exclusiveOwner(of device: USBTransportDevice) async throws -> String?

  /// The process or driver that holds interface `interfaceNumber` of `device` exclusively, as the
  /// host reports it, or nil when the interface names no owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` when the provider cannot observe owners.
  func interfaceExclusiveOwner(
    of device: USBTransportDevice,
    interfaceNumber: UInt8
  ) async throws -> String?

  /// Returns once the client that holds interface `interfaceNumber` of `device` exclusively lets go
  /// of it, or the device goes away.
  ///
  /// The platform announces the release; nothing polls.
  func waitForRelease(of device: USBTransportDevice, interfaceNumber: UInt8) async throws
}

extension USBTransportProvider {
  /// Nil: a provider observes no enumeration changes unless it says so.
  public var enumerationChangeCount: UInt64? { nil }

  /// Opens the device at an IOKit location through ``open(_:options:)``.
  ///
  /// - Throws: ``USBTransportError/notFound`` for any other address, which has no USB device.
  public func openCommandChannel(
    at address: ControllerConnectionAddress,
    model: ControllerModelID,
    options: USBTransportOpenOptions
  ) async throws -> any USBTransportSession {
    guard case .ioKit(let locationID, _) = address else { throw USBTransportError.notFound }
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 0,
      vendorID: model.vendorID,
      productID: model.productID,
      locationID: locationID
    )
    return try await open(device, options: options)
  }

  /// Keeps the configured transport profile unchanged.
  public func resolveTransport(
    for _: USBTransportDevice,
    configured: DeviceTransportProfile
  ) async -> USBTransportResolution {
    await Task.yield()
    return USBTransportResolution(profile: configured)
  }

  /// Observes no physical device; returns nil.
  public func physicalDeviceObservation(for _: USBTransportDevice) -> PhysicalDevice? { nil }

  /// Reads no configuration descriptor.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func configurationObservation(
    for _: USBTransportDevice,
    configurationValue _: UInt8
  ) throws -> PhysicalDevice? { throw USBTransportError.notSupported }

  /// Resets no device.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func resetDevice(_: USBTransportDevice) throws { throw USBTransportError.notSupported }

  /// Names no exclusive owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func exclusiveOwner(of _: USBTransportDevice) throws -> String? {
    throw USBTransportError.notSupported
  }

  /// Names no interface owner.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func interfaceExclusiveOwner(
    of _: USBTransportDevice,
    interfaceNumber _: UInt8
  ) throws -> String? { throw USBTransportError.notSupported }

  /// Waits for no release.
  ///
  /// - Throws: ``USBTransportError/notSupported`` always.
  public func waitForRelease(of _: USBTransportDevice, interfaceNumber _: UInt8) throws {
    throw USBTransportError.notSupported
  }
}

/// The stable failure categories that USB transport implementations share.
public enum USBTransportError: Error, Equatable, Sendable {
  /// The transfer timed out.
  case timeout
  /// The device went away.
  case disconnected
  /// The transfer failed with an input/output error.
  case inputOutput
  /// The platform denied access to the device.
  case accessDenied
  /// Another client holds the interface open exclusively.
  ///
  /// `owner` is the interface's `UsbExclusiveOwner` text, or nil when the interface names none.
  case ownedByAnotherClient(owner: String?)
  /// The device, interface or endpoint was not found.
  case notFound
  /// The provider or session does not support the operation.
  case notSupported
  /// A platform error, by its code and message.
  case platform(code: Int32, message: String)

  /// Whether the error is ``timeout``.
  public var isTimeout: Bool { self == .timeout }
  /// Whether the error is ``disconnected``.
  public var isDisconnected: Bool { self == .disconnected }
  /// Whether the error is ``inputOutput``.
  public var isInputOutput: Bool { self == .inputOutput }
}
