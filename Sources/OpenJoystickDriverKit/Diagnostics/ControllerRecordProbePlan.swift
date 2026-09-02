import Foundation

/// Protocol families that the signing-free record probe can exercise over raw USB.
public enum ControllerRecordProbeDriver: String, Sendable {
  case gip = "GIP"
  case xbox360 = "Xbox360"
}

/// A validated raw-USB test plan loaded from a canonical controller record.
public struct ControllerRecordProbePlan: Equatable, Sendable {
  public let name: String
  public let vendorID: UInt16
  public let productID: UInt16
  public let interfaceNumber: Int
  public let transportProfile: DeviceTransportProfile
  public let driver: ControllerRecordProbeDriver
  public let isWirelessReceiver: Bool
  public let startupPackets: [GIPStartupPacket]
  public let keepAlivePolicy: GIPKeepAlivePolicy

  public init(contentsOf url: URL) throws { try self.init(data: Data(contentsOf: url)) }

  public init(data: Data) throws {
    let document: ControllerRecordDocument
    do { document = try JSONDecoder().decode(ControllerRecordDocument.self, from: data) } catch {
      throw ControllerRecordProbeError.invalidProfile(
        "Could not decode controller record: \(error)"
      )
    }

    guard (1...65_535).contains(document.vendorID) else {
      throw ControllerRecordProbeError.invalidProfile("vendor_id must be in 1...65535")
    }
    guard (0...65_535).contains(document.productID) else {
      throw ControllerRecordProbeError.invalidProfile("product_id must be in 0...65535")
    }
    guard document.transport == "usb" else {
      throw ControllerRecordProbeError.invalidProfile(
        "transport must be usb for the signing-free record probe"
      )
    }
    guard let parsedDriver = ControllerRecordProbeDriver(rawValue: document.protocolInfo.driver)
    else { throw ControllerRecordProbeError.unsupportedProtocol(document.protocolInfo.driver) }
    try Self.validateVariant(document.protocolInfo.variant, for: parsedDriver)

    let defaults = parsedDriver == .xbox360 ? (input: 129, output: 1) : (input: 130, output: 2)
    let inputEndpoint = document.usb?.endpoints?.input ?? defaults.input
    let outputEndpoint = document.usb?.endpoints?.output ?? defaults.output
    guard DeviceTransportProfile.inputEndpointRange.contains(inputEndpoint) else {
      throw ControllerRecordProbeError.invalidProfile(
        "usb.endpoints.in must be an IN endpoint in 128...255"
      )
    }
    guard DeviceTransportProfile.outputEndpointRange.contains(outputEndpoint) else {
      throw ControllerRecordProbeError.invalidProfile(
        "usb.endpoints.out must be an OUT endpoint in 1...127"
      )
    }

    let interfaceNumber = document.usb?.interface ?? 0
    guard DeviceTransportProfile.interfaceNumberRange.contains(interfaceNumber) else {
      throw ControllerRecordProbeError.invalidProfile("usb.interface must be in 0...255")
    }
    let configuration = document.usb?.configuration
    guard configuration == nil || configuration == "set1-before-claim" else {
      throw ControllerRecordProbeError.invalidProfile(
        "usb.configuration must be set1-before-claim when present"
      )
    }
    let settleMilliseconds = document.usb?.postHandshakeSettleMilliseconds ?? 0
    guard settleMilliseconds >= 0 else {
      throw ControllerRecordProbeError.invalidProfile(
        "usb.post_handshake_settle_ms must not be negative"
      )
    }
    let (settleNanoseconds, overflow) = UInt64(settleMilliseconds).multipliedReportingOverflow(
      by: DeviceTransportProfile.nanosecondsPerMillisecond
    )
    guard !overflow else {
      throw ControllerRecordProbeError.invalidProfile("usb.post_handshake_settle_ms is too large")
    }

    let parsedStartupPackets = try Self.parseStartupPackets(
      names: document.protocolInfo.startupPackets,
      driver: parsedDriver
    )
    let parsedKeepAlivePolicy = try Self.parseKeepAlivePolicy(
      enabled: document.protocolInfo.keepAliveEnabled,
      driver: parsedDriver
    )

    vendorID = UInt16(document.vendorID)
    productID = UInt16(document.productID)
    name = String(format: "Controller %04x:%04x", document.vendorID, document.productID)
    self.interfaceNumber = interfaceNumber
    transportProfile = DeviceTransportProfile(
      inputEndpoint: UInt8(inputEndpoint),
      outputEndpoint: UInt8(outputEndpoint),
      interfaceNumber: UInt8(interfaceNumber),
      needsSetConfiguration: configuration == "set1-before-claim",
      postHandshakeSettleNanoseconds: settleNanoseconds
    )
    driver = parsedDriver
    isWirelessReceiver =
      parsedDriver == .xbox360 && document.protocolInfo.variant == "xbox360Wireless"
    startupPackets = parsedStartupPackets
    keepAlivePolicy = parsedKeepAlivePolicy
  }

  public func makeParser() -> any InputParser {
    switch driver {
    case .gip:
      GIPParser(
        transportProfile: transportProfile,
        startupPackets: startupPackets,
        keepAlivePolicy: keepAlivePolicy
      )
    case .xbox360:
      Xbox360Parser(
        outEndpoint: transportProfile.outputEndpoint,
        isWirelessReceiver: isWirelessReceiver
      )
    }
  }

  private static func validateVariant(_ variant: String, for driver: ControllerRecordProbeDriver)
    throws
  {
    let supportedVariants: Set<String>
    switch driver {
    case .gip: supportedVariants = ["xboxOne", "unknown"]
    case .xbox360: supportedVariants = ["xbox360", "xbox360Wireless", "unknown"]
    }
    guard supportedVariants.contains(variant) else {
      throw ControllerRecordProbeError.invalidProfile(
        "protocol.variant \(variant) is not valid for \(driver.rawValue)"
      )
    }
  }

  private static func parseStartupPackets(names: [String]?, driver: ControllerRecordProbeDriver)
    throws -> [GIPStartupPacket]
  {
    switch driver {
    case .gip:
      let names = names ?? []
      if names.isEmpty { return GIPStartupPacket.defaultSequence }
      let packets = names.compactMap(GIPStartupPacket.init(rawValue:))
      guard packets.count == names.count else {
        let known = Set(packets.map(\.rawValue))
        let unknown = names.filter { !known.contains($0) }
        throw ControllerRecordProbeError.invalidProfile(
          "Unknown GIP startup packet(s): \(unknown.joined(separator: ", "))"
        )
      }
      return packets
    case .xbox360:
      guard names == nil || names?.isEmpty == true else {
        throw ControllerRecordProbeError.invalidProfile(
          "protocol.startup_packets is only valid for GIP records"
        )
      }
      return []
    }
  }

  private static func parseKeepAlivePolicy(enabled: Bool?, driver: ControllerRecordProbeDriver)
    throws -> GIPKeepAlivePolicy
  {
    guard driver == .gip || enabled == nil else {
      throw ControllerRecordProbeError.invalidProfile(
        "protocol.keep_alive is only valid for GIP records"
      )
    }
    return enabled.map { $0 ? .enabled : .disabled } ?? .enabled
  }

}

/// Errors reported before the probe opens or writes to a physical device.
public enum ControllerRecordProbeError: Error, Equatable, LocalizedError, Sendable {
  case invalidProfile(String)
  case unsupportedProtocol(String)

  public var errorDescription: String? {
    switch self {
    case .invalidProfile(let message): message
    case .unsupportedProtocol(let driver):
      "The signing-free record probe does not support protocol driver \(driver)"
    }
  }
}
