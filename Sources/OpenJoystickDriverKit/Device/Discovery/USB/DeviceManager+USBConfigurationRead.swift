import Foundation

/// Polls in a row in which a raw-USB service's configuration descriptor read may fail before the
/// service is left unclaimed with ``ProtocolBindingReason/configurationUnreadable``.
///
/// At the 500 ms detection cadence the service gets about 2.5 s after it appears to settle.
let usbConfigurationReadAttempts = 5

extension DeviceManager {
  /// Decides what a failed configuration descriptor read of `device` does to its admission.
  ///
  /// - A refusal with an exclusive owner reported records ``ProtocolBindingReason/deviceInUse``
  ///   and holds the service until it re-enumerates or the host reports no owner
  ///   (`releaseHeldUSBServices(in:provider:generation:)`). The owner is the device's, or
  ///   interface 0's when the device names none, because a client such as Steam that holds only
  ///   that interface still makes the host refuse the read while the device property stays empty.
  /// - A refusal with no owner reported on either, or whose owner cannot be read, records
  ///   ``ProtocolBindingReason/configurationUnreadable``: nothing OJD can observe clears it, so
  ///   the service waits for re-enumeration.
  /// - Any other failure is read again on the next poll, up to `usbConfigurationReadAttempts`
  ///   polls in a row, then records ``ProtocolBindingReason/configurationUnreadable``.
  ///
  /// Each outcome logs one line. `.ignored` acknowledges the service, so the poll stops reading it.
  func handleUSBConfigurationReadFailure(
    _ failure: USBConfigurationReadFailure,
    device: USBTransportDevice,
    provider: any USBTransportProvider,
    interfaces: [PhysicalInterfaceSignature],
    generation: UInt64
  ) async -> USBDeviceHandlingOutcome {
    let service = device.serviceAddress
    guard failure == .refused else {
      let attempt = (usbConfigurationReadFailures[service] ?? 0) + 1
      guard attempt >= usbConfigurationReadAttempts else {
        usbConfigurationReadFailures[service] = attempt
        print(
          "[USBTransport] USB configuration descriptor read failed for \(device.serviceID) "
            + "(attempt \(attempt) of \(usbConfigurationReadAttempts)): \(failure); "
            + "reading it again on the next poll"
        )
        return .retry
      }
      usbConfigurationReadFailures.removeValue(forKey: service)
      print(
        "[USBTransport] USB configuration descriptor read failed for \(device.serviceID) "
          + "\(attempt) polls in a row: \(failure); left unclaimed until it re-enumerates"
      )
      recordUnreadableConfiguration(
        device,
        reason: .configurationUnreadable,
        interfaces: interfaces
      )
      return .ignored
    }
    usbConfigurationReadFailures.removeValue(forKey: service)
    let owner: String?
    let ownerNote: String
    do {
      owner = try await currentUSBOwner(of: device, provider: provider)
      ownerNote = owner.map { "held by \($0)" } ?? "the host reports no exclusive owner"
    } catch {
      owner = nil
      ownerNote = "its exclusive owner cannot be read (\(error))"
    }
    guard isCurrentUSBDetection(generation) else { return .retry }
    guard let owner else {
      print(
        "[DeviceManager] USB device \(device.serviceID) refused the configuration read: "
          + "\(ownerNote); left unclaimed until it re-enumerates"
      )
      recordUnreadableConfiguration(
        device,
        reason: .configurationUnreadable,
        interfaces: interfaces
      )
      return .ignored
    }
    heldUSBServices[service] = owner
    print(
      "[DeviceManager] USB device \(device.serviceID) refused the configuration read: "
        + "\(ownerNote); left unclaimed until it re-enumerates or the host reports no owner"
    )
    recordUnreadableConfiguration(device, reason: .deviceInUse, interfaces: interfaces)
    return .ignored
  }

  /// Makes the polling loop attach a held service again once the host reports no exclusive owner
  /// for its device or interface 0, while the USB device stays attached.
  ///
  /// A service whose owner changes stays held. When the owner cannot be read, the service is not
  /// watched further: its record changes to ``ProtocolBindingReason/configurationUnreadable`` and
  /// it waits for re-enumeration, logged once.
  func releaseHeldUSBServices(
    in enumeration: inout USBEnumerationTracker,
    provider: any USBTransportProvider,
    generation: UInt64
  ) async {
    for (service, owner) in heldUSBServices {
      guard let device = enumeration.acknowledgedDevices[service] else { continue }
      let current: String?
      do {
        current = try await currentUSBOwner(of: device, provider: provider)
      } catch {
        guard isCurrentUSBDetection(generation) else { return }
        guard heldUSBServices[service] == owner else { continue }
        heldUSBServices.removeValue(forKey: service)
        print(
          "[DeviceManager] USB device \(device.serviceID): its exclusive owner cannot be read "
            + "(\(error)); left unclaimed until it re-enumerates"
        )
        replaceUnboundReason(of: .usb(service), with: .configurationUnreadable)
        continue
      }
      guard isCurrentUSBDetection(generation) else { return }
      guard current == nil, heldUSBServices[service] == owner else { continue }
      heldUSBServices.removeValue(forKey: service)
      print(
        "[DeviceManager] USB device \(device.serviceID): \(owner) released it; admitting it again"
      )
      clearUnboundDevice(.usb(service))
      enumeration.unacknowledge(device)
    }
  }

  /// Drops the failed-read counts of services that the last successful poll does not list, which
  /// left before the tracker acknowledged them and so produce no detach.
  func pruneUSBConfigurationReadFailures(keeping devices: [USBTransportDevice]) {
    let present = Set(devices.map(\.serviceAddress))
    usbConfigurationReadFailures = usbConfigurationReadFailures.filter { present.contains($0.key) }
  }

  /// The client that holds `device`, or nil when neither the device nor interface 0 names one.
  private func currentUSBOwner(
    of device: USBTransportDevice,
    provider: any USBTransportProvider
  ) async throws -> String? {
    if let owner = try await provider.exclusiveOwner(of: device) { return owner }
    return try await provider.interfaceExclusiveOwner(of: device, interfaceNumber: 0)
  }

  /// Records the service as unbound for `reason`, with the interfaces observed.
  private func recordUnreadableConfiguration(
    _ device: USBTransportDevice,
    reason: ProtocolBindingReason,
    interfaces: [PhysicalInterfaceSignature]
  ) {
    recordUnboundDevice(
      .usb(device.serviceAddress),
      vendorID: device.vendorID,
      productID: device.productID,
      productName: device.productName,
      connection: "USB",
      backend: DeviceAccessBackend(route: device.route),
      reason: reason,
      rejectedCandidates: [],
      interfaces: interfaces
    )
  }
}
