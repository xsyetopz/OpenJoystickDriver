import Foundation

struct RawUSBAdmission {
  let identifier: DeviceIdentifier
  let productName: String?
}

func resolveRawUSBAdmission(
  parserRegistry: ParserRegistry,
  vendorID: UInt16,
  productID: UInt16,
  locationID: UInt32,
  loadDescriptorStrings: () -> (serialNumber: String?, productName: String?)
) -> RawUSBAdmission? {
  let modelIdentifier = DeviceIdentifier(vendorID: vendorID, productID: productID)
  guard parserRegistry.supportsRawUSBPipeline(for: modelIdentifier) else { return nil }

  let descriptorStrings = loadDescriptorStrings()
  return RawUSBAdmission(
    identifier: DeviceIdentifier(
      vendorID: vendorID,
      productID: productID,
      serialNumber: descriptorStrings.serialNumber,
      locationID: locationID
    ),
    productName: descriptorStrings.productName
  )
}

extension DeviceManager {
  // MARK: - Raw USB detection

  func runUSBDetection() async {
    guard let provider = usbTransportProvider else { return }
    print("[DeviceManager] Raw USB detection started")

    var knownServiceIDs: Set<USBTransportServiceIdentity> = []
    var serviceToIdentifier: [USBTransportServiceIdentity: DeviceIdentifier] = [:]

    while !Task.isCancelled {
      do {
        let devices = try await provider.devices()
        let currentServiceIDs = Set(devices.map(\.serviceIdentity))
        for device in devices where !knownServiceIDs.contains(device.serviceIdentity) {
          knownServiceIDs.insert(device.serviceIdentity)
          if let identifier = await handleUSBDeviceAdded(device, provider: provider) {
            serviceToIdentifier[device.serviceIdentity] = identifier
          }
        }
        await removeUSBLostDevices(
          knownServiceIDs: &knownServiceIDs,
          currentServiceIDs: currentServiceIDs,
          serviceToIdentifier: &serviceToIdentifier
        )
      } catch { print("[DeviceManager] Raw USB discovery failed: \(error)") }
      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  private func removeUSBLostDevices(
    knownServiceIDs: inout Set<USBTransportServiceIdentity>,
    currentServiceIDs: Set<USBTransportServiceIdentity>,
    serviceToIdentifier: inout [USBTransportServiceIdentity: DeviceIdentifier]
  ) async {
    for serviceID in knownServiceIDs.subtracting(currentServiceIDs) {
      knownServiceIDs.remove(serviceID)
      if let identifier = serviceToIdentifier.removeValue(forKey: serviceID) {
        let pipeline = pipelines.removeValue(forKey: identifier)
        deviceInfos.removeValue(forKey: identifier)
        lastPhysicalHIDOutputNanoseconds.removeValue(forKey: identifier)
        await pipeline?.stop()
        print("[DeviceManager] USB device removed: \(identifier)")
      }
    }
  }

  @discardableResult private func handleUSBDeviceAdded(
    _ device: USBTransportDevice,
    provider: any USBTransportProvider
  ) async -> DeviceIdentifier? {
    guard
      let admission = resolveRawUSBAdmission(
        parserRegistry: parserRegistry,
        vendorID: device.vendorID,
        productID: device.productID,
        locationID: device.locationID,
        loadDescriptorStrings: {
          (serialNumber: device.serialNumber, productName: device.productName)
        }
      )
    else {
      let modelIdentifier = DeviceIdentifier(vendorID: device.vendorID, productID: device.productID)
      print(
        "[DeviceManager] \(device.route.rawValue) service observed but left unclaimed:"
          + " \(modelIdentifier)"
      )
      return nil
    }

    let identifier = admission.identifier
    guard pipelines[identifier] == nil,
      Self.matchingPhysicalIdentifier(for: identifier, among: pipelines.keys) == nil
    else {
      print("[DeviceManager] Pipeline already exists for \(identifier)")
      return nil
    }

    let productName = controllerDisplayName(
      productName: admission.productName,
      vendorID: device.vendorID,
      productID: device.productID
    )
    print("[DeviceManager] USB device added: \(productName) (\(identifier))")
    let configuredTransportProfile = parserRegistry.transportProfile(for: identifier)
    let transportProfile = await provider.resolveTransportProfile(
      for: device,
      configured: configuredTransportProfile
    )
    deviceInfos[identifier] = DeviceInfo(
      name: productName,
      connection: "USB",
      serialNumber: identifier.serialNumber,
      discoverySource: .rawUSB(route: device.route)
    )
    let parser = parserRegistry.parser(for: identifier, transportProfile: transportProfile)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(device: device),
      parser: parser,
      dispatcher: dispatcher,
      usbTransportProvider: provider,
      transportProfile: transportProfile,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    return identifier
  }
}
