import Foundation

/// Loads the canonical VID/PID controller records bundled with the driver.
struct DeviceCatalog: Sendable {
  private let profiles: [String: DeviceRuntimeProfile]
  private let rawUSBPipelineIdentifiers: Set<String>
  let rawUSBProfileIdentifiers: [DeviceIdentifier]
  let hidProfileIdentifiers: [DeviceIdentifier]

  init() {
    do {
      var loaded: [String: DeviceRuntimeProfile] = [:]
      var hid: [DeviceIdentifier] = []
      var rawUSB: [DeviceIdentifier] = []
      var rawUSBPipelineIdentifiers: Set<String> = []
      for record in try Self.loadRecords() {
        let key = "\(record.vendorID):\(record.productID)"
        guard loaded[key] == nil else { throw CatalogError("duplicate controller identity \(key)") }
        loaded[key] = try Self.makeRuntimeProfile(record)
        if Self.supportsRawUSBPipeline(record) {
          rawUSBPipelineIdentifiers.insert(key)
          rawUSB.append(
            DeviceIdentifier(vendorID: UInt16(record.vendorID), productID: UInt16(record.productID))
          )
        }
        if record.transport == "hid" {
          hid.append(
            DeviceIdentifier(vendorID: UInt16(record.vendorID), productID: UInt16(record.productID))
          )
        }
      }
      profiles = loaded
      self.rawUSBPipelineIdentifiers = rawUSBPipelineIdentifiers
      self.rawUSBProfileIdentifiers = rawUSB.sorted {
        if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
        return $0.productID < $1.productID
      }
      hidProfileIdentifiers = hid.sorted {
        if $0.vendorID != $1.vendorID { return $0.vendorID < $1.vendorID }
        return $0.productID < $1.productID
      }
    } catch { fatalError("[DeviceCatalog] Invalid controller catalog: \(error)") }
  }

  func parserName(for identifier: DeviceIdentifier) -> String {
    profiles[key(for: identifier)]?.parserName ?? "GenericHID"
  }

  func virtualProfile(for identifier: DeviceIdentifier) -> VirtualDeviceProfile {
    profiles[key(for: identifier)]?.virtualProfile ?? .default
  }

  func transportProfile(for identifier: DeviceIdentifier) -> DeviceTransportProfile {
    profiles[key(for: identifier)]?.transportProfile ?? .gipDefault
  }

  func runtimeProfile(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile {
    profiles[key(for: identifier)]
      ?? DeviceRuntimeProfile(
        parserName: "GenericHID",
        virtualProfile: .default,
        transportProfile: .gipDefault,
        protocolVariant: .genericHID,
        mappingFlags: [],
        mappingOptions: [],
        preferredBackends: [.userSpaceHID],
        gipStartupPackets: GIPStartupPacket.defaultSequence,
        gipKeepAlivePolicy: .enabled
      )
  }

  func supportsRawUSBPipeline(for identifier: DeviceIdentifier) -> Bool {
    rawUSBPipelineIdentifiers.contains(key(for: identifier))
  }

  private func key(for identifier: DeviceIdentifier) -> String {
    "\(identifier.vendorID):\(identifier.productID)"
  }

  private static func loadRecords() throws -> [ControllerRecordDocument] {
    let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      .filter { isControllerRecordFilename($0.lastPathComponent) }.sorted {
        $0.lastPathComponent < $1.lastPathComponent
      }
    guard !urls.isEmpty else { throw CatalogError("controller catalog is empty") }

    let decoder = JSONDecoder()
    return try urls.map { url in
      let data = try Data(contentsOf: url)
      do {
        let record = try decoder.decode(ControllerRecordDocument.self, from: data)
        let expectedName = String(format: "%04x-%04x.json", record.vendorID, record.productID)
        guard url.lastPathComponent == expectedName else {
          throw CatalogError("\(url.path): filename must be \(expectedName)")
        }
        return record
      } catch { throw CatalogError("\(url.path): \(error)") }
    }
  }

  private static func isControllerRecordFilename(_ name: String) -> Bool {
    guard name.count == 14, name.hasSuffix(".json") else { return false }
    let stem = name.dropLast(5)
    guard stem[stem.index(stem.startIndex, offsetBy: 4)] == "-" else { return false }
    return stem.enumerated().allSatisfy { offset, character in offset == 4 || character.isHexDigit }
  }

  private static func makeRuntimeProfile(_ record: ControllerRecordDocument) throws
    -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw CatalogError("invalid controller identity \(record.vendorID):\(record.productID)")
    }
    guard record.transport == "usb" || record.transport == "hid" else {
      throw CatalogError("unsupported transport \(record.transport)")
    }
    let driver = record.protocolInfo.driver
    guard let variant = ControllerProtocolVariant(rawValue: record.protocolInfo.variant) else {
      throw CatalogError(
        "unsupported protocol variant \(record.protocolInfo.variant) for \(driver)"
      )
    }

    let flags = record.protocolInfo.flags ?? []

    let defaultEndpoints = driver == "Xbox360" ? (input: 129, output: 1) : (input: 130, output: 2)
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if record.usb != nil && record.transport != "usb" {
      throw CatalogError("USB overrides require usb transport")
    }
    if let configuration = record.usb?.configuration, configuration != "set1-before-claim" {
      throw CatalogError("unsupported USB configuration \(configuration)")
    }
    let interfaceNumber = record.usb?.interface ?? 0
    let settleMilliseconds = record.usb?.postHandshakeSettleMilliseconds ?? 0
    if record.usb?.interface == 0 || record.usb?.postHandshakeSettleMilliseconds == 0 {
      throw CatalogError("protocol-default USB values must be omitted")
    }
    if let endpoints = record.usb?.endpoints,
      endpoints.input == defaultEndpoints.input && endpoints.output == defaultEndpoints.output
    {
      throw CatalogError("protocol-default endpoints must be omitted")
    }
    if let usb = record.usb, usb.interface == nil, usb.configuration == nil,
      usb.postHandshakeSettleMilliseconds == nil, usb.endpoints == nil
    {
      throw CatalogError("empty USB override")
    }
    guard DeviceTransportProfile.inputEndpointRange.contains(inputEndpoint),
      DeviceTransportProfile.outputEndpointRange.contains(outputEndpoint),
      DeviceTransportProfile.interfaceNumberRange.contains(interfaceNumber), settleMilliseconds >= 0
    else { throw CatalogError("invalid USB override for \(record.vendorID):\(record.productID)") }

    let packetNames = record.protocolInfo.startupPackets ?? []
    let startupPackets = packetNames.compactMap(GIPStartupPacket.init(rawValue:))
    guard startupPackets.count == packetNames.count else {
      throw CatalogError("unsupported startup packets \(packetNames)")
    }
    guard packetNames.isEmpty || driver == "GIP" else {
      throw CatalogError("startup packets require the GIP parser")
    }
    let keepAlivePolicy: GIPKeepAlivePolicy =
      record.protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled } ?? .enabled
    guard driver == "GIP" || record.protocolInfo.keepAliveEnabled == nil else {
      throw CatalogError("keep-alive policy requires the GIP parser")
    }

    return DeviceRuntimeProfile(
      parserName: driver,
      virtualProfile: .default,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        interfaceNumber: UInt8(interfaceNumber),
        hasInterfaceOverride: record.usb?.interface != nil,
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "set1-before-claim",
        postHandshakeSettleNanoseconds: UInt64(settleMilliseconds)
          * DeviceTransportProfile.nanosecondsPerMillisecond
      ),
      protocolVariant: variant,
      mappingFlags: flags,
      mappingOptions: mappingOptions(from: flags),
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: startupPackets.isEmpty ? GIPStartupPacket.defaultSequence : startupPackets,
      gipKeepAlivePolicy: keepAlivePolicy
    )
  }

  private static func supportsRawUSBPipeline(_ record: ControllerRecordDocument) -> Bool {
    record.transport == "usb" && rawUSBParserNames.contains(record.protocolInfo.driver)
  }

  private static func mappingOptions(from flags: [String]) -> ControllerMappingOptions {
    var result: ControllerMappingOptions = []
    for flag in flags {
      switch flag {
      case "dpadToButtons": result.insert(.dpadToButtons)
      case "triggersToButtons": result.insert(.triggersToButtons)
      case "sticksToNull": result.insert(.sticksToNull)
      case "shareButton": result.insert(.shareButton)
      case "paddles": result.insert(.paddles)
      case "profileButton": result.insert(.profileButton)
      case "shareOffset": result.insert(.shareOffset)
      default: break
      }
    }
    return result
  }

  private static let rawUSBParserNames: Set<String> = ["GIP", "Xbox360"]

  private struct CatalogError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }
  }
}
