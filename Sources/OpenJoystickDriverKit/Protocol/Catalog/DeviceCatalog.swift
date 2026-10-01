import Foundation

/// The controller records the runtime binds with: the bundled catalog and any user records.
struct DeviceCatalog: Sendable {
  /// The catalog every ``ProtocolDriverRegistry`` reads. The service replaces it when the user's
  /// controller records change.
  static let current = Locked(Self())

  private let profiles: [ControllerIdentity: DeviceRuntimeProfile]
  /// Each record's merged document, to tell whether a new record set changes anything.
  let documents: [ControllerIdentity: Data]
  let rawUSBProfileIdentifiers: [DeviceIdentifier]
  let hidProfileIdentifiers: [DeviceIdentifier]

  init(records: ControllerRecordSet = .bundled) {
    var hid: [DeviceIdentifier] = []
    var rawUSB: [DeviceIdentifier] = []
    for identity in records.records.keys.sorted(by: {
      ($0.vendorID, $0.productID) < ($1.vendorID, $1.productID)
    }) {
      let identifier = DeviceIdentifier(vendorID: identity.vendorID, productID: identity.productID)
      if records.records[identity]?.usesRawUSB == true {
        rawUSB.append(identifier)
      } else {
        hid.append(identifier)
      }
    }
    profiles = records.records.mapValues(\.profile)
    documents = records.records.mapValues(\.document)
    rawUSBProfileIdentifiers = rawUSB
    hidProfileIdentifiers = hid
  }

  /// The exact catalog record for this identity; there is no default record.
  func record(for identifier: DeviceIdentifier) -> DeviceRuntimeProfile? {
    let identity = identifier.controllerIdentity
    return profiles[ControllerIdentity(vendorID: identity.vendorID, productID: identity.productID)]
  }

  /// Whether the record sets `ownership: ojd`, so OJD seizes the controller even when macOS
  /// serves it natively. The stream reads it when a device is added.
  func takesOwnership(of identifier: DeviceIdentifier) -> Bool {
    record(for: identifier)?.ownership == .ojd
  }

  /// The runtime profile for one decoded record; the record probe plan builds on it too.
  static func makeRuntimeProfile(_ record: ControllerRecordDocument) throws -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw ControllerRecordProblem(
        "invalid controller identity \(record.vendorID):\(record.productID)"
      )
    }
    let protocolInfo = record.protocolInfo
    let defaultEndpoints = defaultEndpoints(for: protocolInfo.protocolID)
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if record.usb != nil
      && !protocolInfo.protocolID.usesRawUSB(storedVariant: protocolInfo.protocolVariant)
    {
      throw ControllerRecordProblem("USB overrides require a raw-USB protocol family")
    }
    if let configuration = record.usb?.configuration, configuration != "set1-before-claim" {
      throw ControllerRecordProblem("unsupported USB configuration \(configuration)")
    }
    let settleMilliseconds = record.usb?.postHandshakeSettleMilliseconds ?? 0
    let keepAlivePolicy: GIPKeepAlivePolicy =
      protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled } ?? .enabled

    return DeviceRuntimeProfile(
      recordID: String(format: "%04x-%04x", record.vendorID, record.productID),
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "set1-before-claim",
        postHandshakeSettleNanoseconds: UInt64(settleMilliseconds)
          * DeviceTransportProfile.nanosecondsPerMillisecond
      ),
      physicalProtocolID: protocolInfo.protocolID,
      physicalProtocolVariant: protocolInfo.protocolVariant,
      quirks: protocolInfo.quirks,
      capabilityDelta: record.capabilities,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: protocolInfo.initialization ?? GIPStartupPacket.defaultSequence,
      gipKeepAlivePolicy: keepAlivePolicy,
      assemblyPolicy: protocolInfo.assembly,
      ownership: record.ownership ?? .macOS,
      rumbleTemplate: record.rumbleTemplate,
      inputLayout: record.inputLayout
    )
  }

  /// The runtime profile of a row that names only this family and stored variant: default
  /// endpoints on interface 0, the default GIP initialization and keep-alive, and no quirks or
  /// capability deltas. Interface-signature bindings of uncatalogued devices run with it.
  static func familyRuntimeProfile(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    needsSetConfiguration: Bool
  ) -> DeviceRuntimeProfile {
    let endpoints = defaultEndpoints(for: protocolID)
    return DeviceRuntimeProfile(
      recordID: nil,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(endpoints.input),
        outputEndpoint: UInt8(endpoints.output),
        needsSetConfiguration: needsSetConfiguration
      ),
      physicalProtocolID: protocolID,
      physicalProtocolVariant: protocolID.storesVariant ? variant : nil,
      quirks: [],
      capabilityDelta: .none,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: GIPStartupPacket.defaultSequence,
      gipKeepAlivePolicy: .enabled,
      assemblyPolicy: nil,
      ownership: .macOS,
      rumbleTemplate: nil,
      inputLayout: nil
    )
  }

  private static func defaultEndpoints(
    for protocolID: PhysicalProtocolID
  ) -> (input: Int, output: Int) {
    switch protocolID {
    case .xboxXUSB: (input: 129, output: 1)
    case .xboxXID: (input: 129, output: 2)
    default: (input: 130, output: 2)
    }
  }
}
