import Foundation

/// The keys that select a mode; every key present must hold.
///
/// A key the device does not expose facts for does not hold.
public struct ControllerModeMatch: Equatable, Sendable {
  /// An interface the device must expose: its USB class triple and, when set, its primary usage
  /// and its endpoint set.
  public struct InterfaceSignature: Equatable, Sendable {
    /// One endpoint of the set; every field present must hold for the endpoint it is paired with.
    public struct Endpoint: Equatable, Sendable {
      /// The endpoint address; nil does not constrain it.
      public var address: UInt8?
      /// The endpoint direction; nil does not constrain it.
      public var direction: USBEndpointDirection?
      /// The endpoint transfer type; nil does not constrain it.
      public var transferType: USBEndpointTransferType?
      /// The maximum packet size; nil does not constrain it.
      public var maxPacketSize: UInt16?

      /// Creates an endpoint pattern; every field not given does not constrain.
      public init(
        address: UInt8? = nil,
        direction: USBEndpointDirection? = nil,
        transferType: USBEndpointTransferType? = nil,
        maxPacketSize: UInt16? = nil
      ) {
        self.address = address
        self.direction = direction
        self.transferType = transferType
        self.maxPacketSize = maxPacketSize
      }
    }

    /// The USB interface class.
    public let interfaceClass: UInt8
    /// The USB interface subclass.
    public let interfaceSubclass: UInt8
    /// The USB interface protocol.
    public let interfaceProtocol: UInt8
    /// The primary HID usage page; nil does not constrain it.
    public let usagePage: UInt32?
    /// The primary HID usage; nil does not constrain it.
    public let usage: UInt32?
    /// The interface's whole endpoint set; nil does not constrain it.
    public var endpoints: [Endpoint]?
  }

  /// The link every interface of the device reaches the controller over: the observed physical
  /// link, else the link a receiver or dongle record reports, else the host link.
  public var link: PhysicalTransport?
  /// The interface the device must expose; nil does not constrain it.
  public var interfaceSignature: InterfaceSignature?
  /// The manufacturer string the device must report; nil does not constrain it.
  public var manufacturer: String?
  /// The product string the device must report; nil does not constrain it.
  public var product: String?
  /// An inclusive range of the device release number.
  public var bcdDevice: ClosedRange<UInt16>?
  /// Reads of feature reports; they run after every other key holds.
  public var probes: [ControllerModeProbe] = []

  /// Whether the keys other than the probes hold for this device. `receiverRecord` is whether the
  /// model's own record runs a receiver or dongle protocol variant, which is the evidence that its
  /// interfaces reach the controller over a proprietary radio link.
  func holds(for device: PhysicalDevice, receiverRecord: Bool = false) -> Bool {
    if let link {
      let links = Set(
        (device.interfaces ?? []).map {
          $0.physicalTransport ?? (receiverRecord ? .proprietaryRadioReceiver : $0.hostTransport)
        }
      )
      guard links == [link] else { return false }
    }
    if let interfaceSignature {
      guard (device.interfaces ?? []).contains(where: interfaceSignature.matches) else {
        return false
      }
    }
    if let manufacturer, device.manufacturer != manufacturer { return false }
    if let product, device.productName != product { return false }
    if let bcdDevice {
      guard let release = device.deviceRelease, bcdDevice.contains(release) else { return false }
    }
    return true
  }
}

extension ControllerModeMatch.InterfaceSignature {
  /// Whether `interface` has this signature's class triple, its primary HID usage, and endpoints
  /// that pair with the listed ones.
  func matches(_ interface: PhysicalInterfaceSignature) -> Bool {
    guard interface.interfaceClass == interfaceClass,
      interface.interfaceSubclass == interfaceSubclass,
      interface.interfaceProtocol == interfaceProtocol
    else { return false }
    let primary = interface.hidLayout?.primaryUsage
    if let usagePage, primary?.usagePage != usagePage { return false }
    if let usage, primary?.usage != usage { return false }
    if let endpoints { return Self.pair(endpoints[...], with: interface.endpoints) }
    return true
  }

  /// Whether every listed endpoint pairs with a distinct endpoint of the interface and none is left
  /// over.
  ///
  /// An interface that reports no endpoints never pairs.
  private static func pair(
    _ wanted: ArraySlice<Endpoint>,
    with actual: [PhysicalEndpointSignature]?
  )
    -> Bool
  {
    guard let actual, wanted.count == actual.count else { return false }
    guard let first = wanted.first else { return true }
    for (index, candidate) in actual.enumerated() where first.accepts(candidate) {
      var rest = actual
      rest.remove(at: index)
      if pair(wanted.dropFirst(), with: rest) { return true }
    }
    return false
  }
}

extension ControllerModeMatch.InterfaceSignature.Endpoint {
  /// Whether `endpoint` agrees with every field that this endpoint pattern sets.
  func accepts(_ endpoint: PhysicalEndpointSignature) -> Bool {
    (address == nil || address == endpoint.address)
      && (direction == nil || direction == endpoint.direction)
      && (transferType == nil || transferType == endpoint.transferType)
      && (maxPacketSize == nil || maxPacketSize == endpoint.maxPacketSize)
  }
}

/// The reason a mode serves nothing: OJD sends the device no data and publishes no gamepad.
public enum ControllerIdleReason: String, Equatable, Sendable {
  /// A receiver that has no controller linked to it.
  case noControllerLinked = "NoControllerLinked"
  /// A controller in bootloader state, where a write risks a bad firmware image.
  case bootloader = "Bootloader"
}

/// One alternative mode of a controller model: the protocol it runs and the keys that must all hold
/// for it to be selected.
///
/// The record's `default` mode is not listed; it has no keys.
public struct ControllerMode: Equatable, Sendable {
  /// The mode ID that records and selections name.
  public let id: String
  /// The protocol the mode runs.
  public let physicalProtocolID: PhysicalProtocolID
  /// The protocol variant the mode runs; nil for none.
  public let physicalProtocolVariant: PhysicalProtocolVariantID?
  /// The protocol parameters the mode sets.
  public let parameters: ProtocolParameters
  /// The named GIP packets sent at startup.
  public let gipStartupPackets: [String]
  /// The GIP keep-alive policy of the mode.
  public let gipKeepAlivePolicy: GIPKeepAlivePolicy
  /// The assembly policy of the mode; nil for none.
  public let assemblyPolicy: ControllerAssemblyPolicy?
  /// The keys that must all hold for the mode to be selected.
  public let match: ControllerModeMatch
  /// The interface numbers this mode drives; nil keeps the default binding.
  public let interfaceRange: ClosedRange<UInt8>?
  /// The steps this mode runs; the profile's session is replaced by it as a whole.
  public let session: ControllerSession
  /// Why the mode serves nothing while it matches; nil for a mode that serves the device.
  public let idle: ControllerIdleReason?

  /// The probes of this mode's match.
  public var probes: [ControllerModeProbe] { match.probes }
}

extension DeviceRuntimeProfile {
  /// This profile running the named mode; the profile itself for nil, and nil for a mode the
  /// record does not have.
  func applying(modeID: String?) -> DeviceRuntimeProfile? {
    guard let modeID else { return self }
    guard let mode = modes.first(where: { $0.id == modeID }) else { return nil }
    var profile = self
    profile.physicalProtocolID = mode.physicalProtocolID
    profile.physicalProtocolVariant = mode.physicalProtocolVariant
    profile.parameters = mode.parameters
    profile.gipStartupPackets = mode.gipStartupPackets
    profile.gipKeepAlivePolicy = mode.gipKeepAlivePolicy
    profile.assemblyPolicy = mode.assemblyPolicy
    profile.interfaceRange = mode.interfaceRange ?? interfaceRange
    profile.session = mode.session
    profile.idleReason = mode.idle
    profile.transportProfile = transportProfile.settling(
      milliseconds: mode.session.settleMilliseconds
    )
    profile.modeID = modeID
    return profile
  }
}

/// How a model's mode was chosen.
public enum ControllerModeSelection: Equatable, Sendable {
  /// The record has no mode besides `default`.
  case noModes
  /// Every key of the named mode held.
  case matched(String)
  /// No mode's keys all held, so the default mode runs; a record without one leaves the device
  /// unsupported.
  case noModeMatched
  /// The device is not on an IOHID route, which is the only route a probe can read, so the
  /// default mode runs; a record without one leaves the device unsupported.
  case noProbeRoute
  /// A probe got no usable reply, so the default mode runs; a record without one leaves the device
  /// unsupported.
  case probeInconclusive(reportID: UInt8)

  /// The selected mode's ID; nil selects the default mode, which a record without one lacks.
  public var modeID: String? {
    if case .matched(let id) = self { return id }
    return nil
  }
}

/// Picks a model's mode.
///
/// Modes are tried in record order and the first whose keys all hold wins. The keys read from the
/// enumerated device are checked first, and a mode's probes only once those hold. A probe without a
/// usable reply ends the selection at the default mode and never disables a controller whose
/// record has one. A record without a `default` mode leaves the device unsupported when no mode is
/// selected.
public enum ControllerModeSelector {
  /// Picks the mode of `profile` that `device` runs, and logs the outcome.
  ///
  /// Probes read HID feature reports through `reader`, so they run only on the IOHID route
  /// (`backend` is `.hid`). One read serves every probe of the same report ID and length.
  /// - Parameters:
  ///   - profile: The record whose modes are tried in order.
  ///   - model: The controller model, named in the log.
  ///   - backend: The route the device is accessed on; probes run only on `.hid`.
  ///   - reader: Reads the feature reports that probes ask for.
  ///   - device: The enumerated device whose facts the mode keys test.
  ///   - log: Receives one line for each outcome that is not a plain match.
  /// - Returns: The ``ControllerModeSelection``; ``ControllerModeSelection/modeID`` is nil for the
  ///   default mode.
  @preconcurrency
  public static func select(
    from profile: DeviceRuntimeProfile,
    model: ControllerModelID,
    backend: DeviceAccessBackend,
    reader: any ControllerModeProbeReader,
    device: PhysicalDevice = PhysicalDevice(),
    log: @Sendable (String) -> Void = { print($0) }
  ) async -> ControllerModeSelection {
    guard !profile.modes.isEmpty else { return .noModes }
    let fallback = profile.hasDefaultMode ? "the default mode is used" : "the device is unsupported"
    let receiverRecord =
      profile.physicalProtocolVariant.map { [.receiver, .dongle].contains($0) } ?? false
    // Two pads of one model differ in the log only by their location.
    let name =
      String(format: "%04X:%04X", model.vendorID, model.productID)
      + (device.physicalLocationIdentifier.map { String(format: " at location 0x%08X", $0) } ?? "")
    // One read per report serves every probe of that report.
    var replies: [Int: PhysicalHIDReportResult<Data>] = [:]
    for mode in profile.modes where mode.match.holds(for: device, receiverRecord: receiverRecord) {
      var held = true
      for probe in mode.probes {
        guard backend == .hid else {
          log(
            "[DeviceManager] Mode probes of \(name) read HID feature reports; the"
              + " \(backend.rawValue) route has none, so \(fallback)"
          )
          return .noProbeRoute
        }
        let key = Int(probe.reportID) * 65_536 + probe.length
        let reply: PhysicalHIDReportResult<Data>
        if let cached = replies[key] {
          reply = cached
        } else {
          reply = await reader.readFeatureReport(probe.request)
          replies[key] = reply
        }
        switch probe.verdict(for: reply) {
        case .satisfied: continue
        case .unsatisfied: held = false
        case .inconclusive:
          log(
            "[DeviceManager] Mode probe of \(name) got no reply for report=\(probe.reportID)"
              + " (mode \(mode.id)); \(fallback)"
          )
          return .probeInconclusive(reportID: probe.reportID)
        }
        if !held { break }
      }
      if held {
        log("[DeviceManager] Mode keys of \(name) selected mode \(mode.id)")
        return .matched(mode.id)
      }
    }
    let seen = (device.interfaces ?? []).compactMap { interface -> String? in
      guard let kind = interface.interfaceClass, let subclass = interface.interfaceSubclass,
        let code = interface.interfaceProtocol
      else { return nil }
      return String(format: "%02X/%02X/%02X", kind, subclass, code)
    }
    log(
      "[DeviceManager] No mode of \(name) matched; \(fallback)"
        + " (interface classes seen: \(seen.isEmpty ? "none" : seen.joined(separator: " ")))"
    )
    return .noModeMatched
  }
}
