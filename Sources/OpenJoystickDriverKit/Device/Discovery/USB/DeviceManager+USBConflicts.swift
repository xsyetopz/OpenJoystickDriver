import Foundation

extension USBTransportProvider {
  /// Completes a raw-USB resolution from the device's own descriptor of configuration 1 when the
  /// passive registry facts carry no usable interface with endpoints: the IORegistry carries
  /// interface class triples but no endpoint descriptors, and an unconfigured device has no
  /// interfaces.
  ///
  /// The descriptor is read without SET_CONFIGURATION, and claimed-interface validation checks it
  /// before any write. The pipeline's open sends the only SET_CONFIGURATION: rows that set it
  /// before the claim already request it, and a device observed unconfigured gets it too, since
  /// none of its interfaces can be claimed otherwise. Explicit catalog endpoint pins stay
  /// authoritative, but a pinned device is read too, so validation can confirm its interface class
  /// and that the pinned endpoints exist.
  ///
  /// - Throws: ``USBConfigurationReadFailure`` when the descriptor cannot be read, so the caller
  ///   decides whether to read it again instead of running on unvalidated or family-default
  ///   endpoints.
  public func resolveUSBConfiguration(
    _ device: USBTransportDevice,
    passive: USBTransportResolution
  ) async throws(USBConfigurationReadFailure) -> USBTransportResolution {
    let configured = settingConfigurationIfUnconfigured(
      passive.profile,
      observed: passive.physicalDevice
    )
    let passiveResolution = USBTransportResolution(
      profile: configured,
      physicalDevice: passive.physicalDevice
    )
    guard device.route == .rawUSB,
      USBDescriptorTransportResolver.discover(
        configured: configured,
        observed: passive.physicalDevice
      ) == nil
    else { return passiveResolution }
    let observed: PhysicalDevice?
    do {
      observed = try await configurationObservation(for: device, configurationValue: 1)
    } catch USBTransportError.notSupported {
      // The provider has no descriptor source; the passive facts are all there is.
      return passiveResolution
    } catch USBTransportError.accessDenied, USBTransportError.ownedByAnotherClient {
      throw .refused
    } catch {
      throw .failed(String(describing: error))
    }
    guard let observed else { throw .unavailable }
    return USBTransportResolution(
      profile: USBDescriptorTransportResolver.resolve(configured: configured, observed: observed),
      physicalDevice: observed
    )
  }
}

/// Why the configuration descriptor of a raw-USB device could not be read.
public enum USBConfigurationReadFailure: Error, Equatable, Sendable, CustomStringConvertible {
  /// The host refused the read: another owner holds the device exclusively
  /// (``USBTransportError/ownedByAnotherClient(owner:)``, such as Steam on macOS 27), or the host
  /// denies OJD access to it (``USBTransportError/accessDenied``).
  case refused
  /// The host reports no descriptor of configuration 1 for the device's service.
  case unavailable
  /// The read failed with another error, described as the provider reported it.
  case failed(String)

  /// The text that names the failure in logs.
  ///
  /// A refusal reads `accessDenied`, a missing descriptor reads `descriptor unavailable` and
  /// another failure reads the error text of the provider.
  public var description: String {
    switch self {
    case .refused: return "accessDenied"
    case .unavailable: return "descriptor unavailable"
    case .failed(let error): return error
    }
  }
}

/// The profile with SET_CONFIGURATION required when the observed device has no interfaces and no
/// active configuration, and the profile unchanged otherwise.
private func settingConfigurationIfUnconfigured(
  _ profile: DeviceTransportProfile,
  observed: PhysicalDevice?
) -> DeviceTransportProfile {
  guard !profile.needsSetConfiguration, let observed, (observed.interfaces ?? []).isEmpty,
    (observed.configurationValue ?? 0) == 0
  else { return profile }
  return DeviceTransportProfile(
    inputEndpoint: profile.inputEndpoint,
    outputEndpoint: profile.outputEndpoint,
    interfaceNumber: profile.interfaceNumber,
    alternateSetting: profile.alternateSetting,
    hasInterfaceOverride: profile.hasInterfaceOverride,
    hasEndpointOverride: profile.hasEndpointOverride,
    needsSetConfiguration: true,
    postHandshakeSettleNanoseconds: profile.postHandshakeSettleNanoseconds
  )
}

extension DeviceManager {
  /// The logical-controller key of a raw-USB service claiming the profile's interface.
  static func usbIdentifier(
    for device: USBTransportDevice,
    claiming profile: DeviceTransportProfile
  ) -> LogicalControllerID {
    LogicalControllerID(
      vendorID: device.vendorID,
      productID: device.productID,
      serialNumber: device.serialNumber,
      locationID: device.locationID,
      interfaceNumber: profile.interfaceNumber
    )
  }

  /// Whether a raw-USB admission of `identifier` through `service` conflicts with a running
  /// pipeline.
  ///
  /// With `yieldingHID`, a HID pipeline of the same controller is not a conflict, because
  /// ``yieldHIDPipelines(to:)`` stops it before the raw-USB pipeline starts. A native pass-through
  /// HID controller is never yielded.
  func hasUSBPipelineConflict(
    for identifier: LogicalControllerID,
    service: ControllerConnectionAddress,
    yieldingHID: Bool = false
  ) -> Bool {
    Self.hasUSBPipelineConflict(
      for: identifier,
      service: service,
      among: pipelines.keys.filter { !yieldingHID || !yieldsToRawUSB($0) }.map {
        ($0, deviceInfos[$0]?.usbTransportDevice?.serviceAddress)
      }
    )
  }

  /// Whether `key` names a HID pipeline that yields to raw USB: any HID pipeline except a native
  /// pass-through controller.
  private func yieldsToRawUSB(_ key: LogicalControllerID) -> Bool {
    guard let info = deviceInfos[key], case .hid = info.discoverySource else { return false }
    return info.physicalDevice?.nativePassThrough != true
  }

  /// Raw USB takes precedence over HID for a controller reachable by both, so the route does not
  /// depend on which admission ran first.
  ///
  /// Stops each HID pipeline that serves the same physical controller as `identifier` and releases
  /// its input claim, leaving the device unseized.
  func yieldHIDPipelines(to identifier: LogicalControllerID) async {
    let yielded = deviceInfos.keys.filter {
      yieldsToRawUSB($0) && Self.isSamePhysicalController($0, identifier)
    }
    for key in yielded {
      print("[DeviceManager] Raw USB takes precedence over HID for \(key)")
      if let info = deviceInfos[key], let physicalDevice = info.physicalDevice,
        let connectionID = info.hidConnectionID, let address = key.hidRoutingAddress
      {
        yieldedHIDConnections[connectionID] = YieldedHIDConnection(
          identifier: key,
          snapshot: HIDDeviceConnectionSnapshot(
            connection: HIDDeviceConnection(
              connectionID: connectionID,
              physicalDevice: physicalDevice,
              routingAddress: address
            ),
            ownership: info.hidInputOwnership
          )
        )
      }
      await tearDownHIDDevice(identifier: key)
      if let address = key.hidRoutingAddress {
        _ = await hidManager.releaseInputClaim(address: address)
      }
    }
  }

  /// Whether a native pass-through HID controller serves the same physical controller as
  /// `identifier`. macOS serves it, so raw USB does not claim it.
  func hasNativeHIDController(sameAs identifier: LogicalControllerID) -> Bool {
    deviceInfos.contains { key, info in
      guard case .hid = info.discoverySource, info.physicalDevice?.nativePassThrough == true else {
        return false
      }
      return Self.isSamePhysicalController(key, identifier)
    }
  }

  /// Leaves a raw-USB service unclaimed while a native HID controller serves its controller.
  ///
  /// The caller acknowledges the service, so the poll does not retry it or repeat the log line;
  /// `releaseNativeShadowedUSBServices(in:)` admits it again once the native controller is gone.
  func deferToNativeHID(_ device: USBTransportDevice, identifier: LogicalControllerID) -> Bool {
    guard hasNativeHIDController(sameAs: identifier) else { return false }
    if nativeShadowedUSBServices.updateValue(identifier, forKey: device.serviceAddress) == nil {
      print("[DeviceManager] Native HID serves \(identifier); raw USB left unclaimed")
    }
    return true
  }

  /// Makes the polling loop attach a shadowed service again once no native HID controller serves
  /// its controller, while the USB device stays attached.
  func releaseNativeShadowedUSBServices(in enumeration: inout USBEnumerationTracker) {
    for (service, identifier) in nativeShadowedUSBServices
    where !hasNativeHIDController(sameAs: identifier) {
      nativeShadowedUSBServices.removeValue(forKey: service)
      if let device = enumeration.acknowledgedDevices[service] { enumeration.unacknowledge(device) }
    }
  }

  /// Native pass-through wins over raw USB for a controller reachable by both, so the route does
  /// not depend on which admission ran first.
  ///
  /// Removes and stops each raw-USB pipeline of the same physical controller as `identifier`, which
  /// closes its USB claim, and drops the HID connections that had yielded to them. The service
  /// stays acknowledged and is remembered as shadowed, so it is admitted again if the native
  /// controller goes away.
  func yieldRawUSBPipelines(toNative identifier: LogicalControllerID) async {
    let raw = deviceInfos.filter { key, info in
      info.usbTransportDevice != nil && Self.isSamePhysicalController(key, identifier)
    }
    guard !raw.isEmpty else { return }
    for (key, info) in raw {
      print("[DeviceManager] Native HID takes precedence over raw USB for \(key)")
      if let service = info.usbTransportDevice?.serviceAddress {
        nativeShadowedUSBServices[service] = key
      }
    }
    yieldedHIDConnections = yieldedHIDConnections.filter {
      !Self.isSamePhysicalController($0.value.identifier, identifier)
    }
    let removed = raw.keys.compactMap(removeUSBRole)
    notifyServiceStatusChanged()
    for pipeline in removed { await pipeline.stop() }
  }

  /// Polls with every raw-USB pipeline of a yielded controller still failing to start a session
  /// before its HID route returns, so one transient failure does not flap the route.
  private static let yieldedHIDRestoreFailedPolls = 2

  /// Restores the HID route of a yielded controller whose raw-USB session never starts.
  ///
  /// The raw-USB pipelines are removed and stopped, and the HID connection is admitted again. The
  /// USB service stays acknowledged, so raw USB is not retried until the device re-enumerates.
  func restoreYieldedHIDRoutes() async {
    for connectionID in Array(yieldedHIDConnections.keys) {
      guard var yielded = yieldedHIDConnections[connectionID] else { continue }
      let raw = pipelines.filter {
        deviceInfos[$0.key]?.usbTransportDevice != nil
          && Self.isSamePhysicalController($0.key, yielded.identifier)
      }
      var allFailed = !raw.isEmpty
      for pipeline in raw.values where allFailed {
        allFailed = await pipeline.usbSessionStartFailed
      }
      // The awaits above suspend the actor; act only on the pipelines that were just observed.
      guard allFailed, yieldedHIDConnections[connectionID] != nil,
        raw.allSatisfy({ pipelines[$0.key] === $0.value })
      else {
        yieldedHIDConnections[connectionID]?.failedPolls = 0
        continue
      }
      yielded.failedPolls += 1
      yieldedHIDConnections[connectionID] = yielded
      guard yielded.failedPolls >= Self.yieldedHIDRestoreFailedPolls else { continue }
      print(
        "[DeviceManager] Raw USB session never started; restoring HID for \(yielded.identifier)"
      )
      let removed = raw.keys.compactMap { key in removeUSBRole(key).map { (key, $0) } }
      notifyServiceStatusChanged()
      for (_, pipeline) in removed { await pipeline.stop() }
      guard !isStopping, yieldedHIDConnections[connectionID] != nil else { continue }
      yieldedHIDConnections.removeValue(forKey: connectionID)
      let connection = yielded.snapshot.connection
      _ = await hidManager.reacquireInputClaim(address: connection.routingAddress)
      scheduleHIDDeviceInitialization(connection: connection, ownership: yielded.snapshot.ownership)
      await reconcileUnboundHIDClaims()
    }
  }

  /// A raw-USB admission conflicts when its exact logical-controller key is already running, or
  /// when the same physical controller runs through another service: another route, another
  /// location, or HID, whose pipelines carry no service.
  ///
  /// Interfaces of one service never conflict with each other, so each receiver slot can hold its
  /// own pipeline.
  static func hasUSBPipelineConflict(
    for identifier: LogicalControllerID,
    service: ControllerConnectionAddress,
    among pipelines: [(key: LogicalControllerID, service: ControllerConnectionAddress?)]
  ) -> Bool {
    pipelines.contains { key, keyService in
      key == identifier || keyService != service && isSamePhysicalController(key, identifier)
    }
  }

  /// Whether two keys reached through different services belong to one physical controller: the
  /// same identity with a serial number, or, since a serial-less identity names only a model, the
  /// same identity at the same location.
  ///
  /// A USB device's HID interfaces report its USB location.
  static func isSamePhysicalController(
    _ lhs: LogicalControllerID,
    _ rhs: LogicalControllerID
  ) -> Bool {
    lhs.hardware == rhs.hardware
      && (lhs.hardware.identifiesPhysicalDevice
        || lhs.address?.locationID == rhs.address?.locationID)
  }

  /// The running raw-USB pipeline that serves the same physical controller as a HID key, if any.
  func rawUSBIdentifier(
    servingSameControllerAs identifier: LogicalControllerID
  ) -> LogicalControllerID? {
    pipelines.keys.first {
      deviceInfos[$0]?.usbTransportDevice != nil && Self.isSamePhysicalController($0, identifier)
    }
  }
}

/// A HID connection stopped for a raw-USB pipeline of its controller, with the key it ran under.
struct YieldedHIDConnection {
  /// The key the HID pipeline ran under.
  let identifier: LogicalControllerID
  /// The connection and ownership to admit again.
  let snapshot: HIDDeviceConnectionSnapshot
  /// The polls in a row in which every raw-USB pipeline of the controller failed to start a
  /// session.
  var failedPolls = 0
}
