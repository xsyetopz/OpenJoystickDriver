import Foundation

/// The controller records the runtime binds with: the bundled catalog and any user records.
package struct DeviceCatalog: Sendable {
  /// The catalog every ``ProtocolDriverRegistry`` reads.
  ///
  /// The service replaces it when the user's controller records change.
  package static let current = Locked(Self())

  /// The runtime profile of each model.
  private let profiles: [ControllerModelID: DeviceRuntimeProfile]
  /// Each record's merged document, to tell whether a new record set changes anything.
  let documents: [ControllerModelID: Data]
  /// The models whose records run a raw-USB protocol, in model order.
  let rawUSBModels: [ControllerModelID]
  /// The models whose records run a HID protocol, in model order.
  let hidModels: [ControllerModelID]

  /// Creates a catalog from a record set, sorting each model into the raw-USB or HID list.
  init(records: ControllerRecordSet = .bundled) {
    var hid: [ControllerModelID] = []
    var rawUSB: [ControllerModelID] = []
    for model in records.records.keys.sorted() {
      if records.records[model]?.usesRawUSB == true {
        rawUSB.append(model)
      } else {
        hid.append(model)
      }
    }
    profiles = records.records.mapValues(\.profile)
    documents = records.records.mapValues(\.document)
    rawUSBModels = rawUSB
    hidModels = hid
  }

  /// The exact catalog record for this model; there is no default record.
  func record(for model: ControllerModelID) -> DeviceRuntimeProfile? { profiles[model] }

  /// The exact catalog record running the named mode; nil when the record does not have it.
  func record(for model: ControllerModelID, modeID: String?) -> DeviceRuntimeProfile? {
    profiles[model]?.applying(modeID: modeID)
  }

  /// Whether the record sets `server: ojd`, so OJD seizes the controller even when macOS serves it
  /// natively.
  ///
  /// The stream reads it when a device is added.
  package func takesOwnership(of model: ControllerModelID) -> Bool {
    record(for: model)?.server == .ojd
  }

  /// The runtime profile for one decoded record; the record probe plan builds on it too.
  static func makeRuntimeProfile(_ record: ControllerRecordDocument) throws -> DeviceRuntimeProfile
  {
    guard (1...65_535).contains(record.vendorID), (0...65_535).contains(record.productID) else {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "invalid controller identity \(record.vendorID):\(record.productID)"
      )
    }
    let protocolInfo = record.protocolInfo
    let defaultEndpoints = protocolInfo.protocolID.protocolDescription.endpoints
    let inputEndpoint = record.usb?.endpoints?.input ?? defaultEndpoints.input
    let outputEndpoint = record.usb?.endpoints?.output ?? defaultEndpoints.output
    if let configuration = record.usb?.configuration,
      configuration != "SetConfiguration1BeforeClaim"
    {
      throw ControllerRecordProblem(
        code: .invalidControllerRecord,
        "unsupported USB configuration \(configuration)"
      )
    }
    let session = record.defaultMode.session
    let keepAlivePolicy: GIPKeepAlivePolicy =
      protocolInfo.keepAliveEnabled.map { $0 ? .enabled : .disabled } ?? .enabled

    return DeviceRuntimeProfile(
      recordID: String(format: "%04x-%04x", record.vendorID, record.productID),
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(inputEndpoint),
        outputEndpoint: UInt8(outputEndpoint),
        hasEndpointOverride: record.usb?.endpoints != nil,
        needsSetConfiguration: record.usb?.configuration == "SetConfiguration1BeforeClaim",
        postHandshakeSettleNanoseconds: DeviceTransportProfile.settleNanoseconds(
          milliseconds: session.settleMilliseconds
        )
      ),
      physicalProtocolID: protocolInfo.protocolID,
      physicalProtocolVariant: protocolInfo.protocolVariant,
      parameters: protocolInfo.parameters,
      capabilityDelta: record.capabilities,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: protocolInfo.initialization ?? [],
      gipKeepAlivePolicy: keepAlivePolicy,
      assemblyPolicy: protocolInfo.assembly,
      server: record.server ?? .system,
      session: session,
      inputLayouts: record.inputLayouts,
      hidUsageMap: record.hidUsageMap,
      tuning: record.tuning,
      route: record.route,
      bluetoothLEVibrationCharacteristic: record.bluetoothLE?.vibrationCharacteristic,
      interfaceRange: record.defaultMode.interfaceRange,
      modes: record.modes.filter { !$0.isDefault }.map(\.mode)
    )
  }

  /// The runtime profile of a row that names only this family and stored variant: default endpoints
  /// on interface 0, the default GIP initialization and keep-alive, and no parameters or capability
  /// deltas.
  ///
  /// Interface-signature bindings of uncatalogued devices run with it.
  static func familyRuntimeProfile(
    _ protocolID: PhysicalProtocolID,
    variant: PhysicalProtocolVariantID?,
    needsSetConfiguration: Bool
  ) -> DeviceRuntimeProfile {
    let endpoints = protocolID.protocolDescription.endpoints
    return DeviceRuntimeProfile(
      recordID: nil,
      transportProfile: DeviceTransportProfile(
        inputEndpoint: UInt8(endpoints.input),
        outputEndpoint: UInt8(endpoints.output),
        needsSetConfiguration: needsSetConfiguration
      ),
      physicalProtocolID: protocolID,
      physicalProtocolVariant: protocolID.storesVariant ? variant : nil,
      parameters: .none,
      capabilityDelta: .none,
      preferredBackends: [.userSpaceHID],
      gipStartupPackets: [],
      gipKeepAlivePolicy: .enabled,
      assemblyPolicy: nil,
      server: .system,
      session: .none,
      inputLayouts: nil,
      tuning: .none
    )
  }
}
