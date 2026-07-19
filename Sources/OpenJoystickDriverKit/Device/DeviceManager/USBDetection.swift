import Foundation
import SwiftUSB

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
  // MARK: - USB detection (class 0xFF)

  func runUSBDetection() async {
    print("[DeviceManager] USB detection started" + " (class 0xFF)")
    ensureUSBContext()
    guard let context = usbContext else {
      print("[DeviceManager] Failed to create USBContext")
      return
    }

    var knownLocations: Set<String> = []
    var locationToIdentifier: [String: DeviceIdentifier] = [:]

    while !Task.isCancelled {
      let (currentKeys, addedDevices) = await usbDetectCurrentDevices(
        context: context,
        knownLocations: knownLocations
      )

      updateUSBKnownLocations(
        &knownLocations,
        currentKeys: currentKeys,
        addedDevices: addedDevices,
        locationToIdentifier: &locationToIdentifier
      )

      await removeUSBLostDevices(
        knownLocations: &knownLocations,
        currentKeys: currentKeys,
        locationToIdentifier: &locationToIdentifier
      )

      try? await Task.sleep(nanoseconds: usbDetectionPollNanoseconds)
    }
  }

  private func usbDetectCurrentDevices(context: USBContext, knownLocations: Set<String>) async -> (
    Set<String>, [(device: USBDevice, key: String)]
  ) {
    var currentKeys: Set<String> = []
    var addedDevices: [(device: USBDevice, key: String)] = []
    let stream = context.findDevices(deviceClass: usbVendorSpecificClass, findAll: true)
    for await device in stream {
      let key = "\(device.bus):\(device.address)"
      currentKeys.insert(key)
      if !knownLocations.contains(key) { addedDevices.append((device, key)) }
    }
    return (currentKeys, addedDevices)
  }

  private func updateUSBKnownLocations(
    _ knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    addedDevices: [(device: USBDevice, key: String)],
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) {
    for (device, key) in addedDevices {
      knownLocations.insert(key)
      if let id = handleUSBDeviceAdded(device) { locationToIdentifier[key] = id }
    }
  }

  private func removeUSBLostDevices(
    knownLocations: inout Set<String>,
    currentKeys: Set<String>,
    locationToIdentifier: inout [String: DeviceIdentifier]
  ) async {
    let removedKeys = knownLocations.subtracting(currentKeys)
    for key in removedKeys {
      knownLocations.remove(key)
      if let id = locationToIdentifier.removeValue(forKey: key) {
        let pipeline = pipelines.removeValue(forKey: id)
        deviceInfos.removeValue(forKey: id)
        lastPhysicalHIDOutputNanoseconds.removeValue(forKey: id)
        await pipeline?.stop()
        print("[DeviceManager] USB device removed: \(id)")
      }
    }
  }

  func ensureUSBContext() {
    if usbContext != nil { return }
    do { usbContext = try USBContext() } catch {
      usbContext = nil
      print("[DeviceManager] Failed to create USBContext: \(error)")
    }
  }

  @discardableResult private func handleUSBDeviceAdded(_ device: USBDevice) -> DeviceIdentifier? {
    let vendorID = device.idVendor
    let productID = device.idProduct
    let locationID = UInt32((UInt32(device.bus) << 8) | UInt32(device.address))
    guard
      let admission = resolveRawUSBAdmission(
        parserRegistry: parserRegistry,
        vendorID: vendorID,
        productID: productID,
        locationID: locationID,
        loadDescriptorStrings: {
          (serialNumber: try? device.getSerialNumber(), productName: try? device.getProduct())
        }
      )
    else {
      let modelIdentifier = DeviceIdentifier(vendorID: vendorID, productID: productID)
      print("[DeviceManager] Raw USB device observed but left unclaimed: \(modelIdentifier)")
      return nil
    }

    let identifier = admission.identifier
    let serial = identifier.serialNumber

    guard pipelines[identifier] == nil else {
      print("[DeviceManager] Pipeline already exists" + " for \(identifier)")
      return nil
    }

    let productName = controllerDisplayName(
      productName: admission.productName,
      vendorID: vendorID,
      productID: productID
    )
    deviceInfos[identifier] = DeviceInfo(name: productName, connection: "USB", serialNumber: serial)
    print("[DeviceManager] USB device added: \(productName) (\(identifier))")
    let configuredTransport = parserRegistry.transportProfile(for: identifier)
    let transportProfile = USBDescriptorTransportResolver.resolve(
      device: device,
      configured: configuredTransport
    )
    let parser = parserRegistry.parser(for: identifier, transportProfile: transportProfile)
    let pipeline = DevicePipeline(
      identifier: identifier,
      transport: .usb(vendorID: vendorID, productID: productID),
      parser: parser,
      dispatcher: dispatcher,
      usbContext: usbContext,
      transportProfile: transportProfile,
      externalOutputAllowed: externalOutputAllowed
    )
    pipelines[identifier] = pipeline
    Task { await pipeline.start() }
    if !pipeline.requiresInputConnectionBeforeOutput() {
      Task { await dispatcher.dispatch(events: [], from: identifier) }
    }
    return identifier
  }
}
