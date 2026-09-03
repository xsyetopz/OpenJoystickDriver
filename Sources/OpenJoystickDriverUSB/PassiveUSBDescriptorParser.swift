import Foundation

public enum PassiveUSBConfigurationDescriptorParser {
  public static let maxBlobSize = 65_535

  public static func parse(
    _ bytes: [UInt8],
    negotiatedSpeed: PassiveUSBNegotiatedSpeed? = nil,
    superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext? = nil
  ) throws -> PassiveUSBConfigurationDescriptor {
    guard !bytes.isEmpty, bytes.count <= maxBlobSize else {
      throw PassiveUSBDescriptorBlobError.unsafeSize
    }
    guard bytes.count >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
    var offset = 0
    var descriptors: [PassiveUSBParsedDescriptor] = []
    var interfaces: [PassiveUSBDescriptorInterface] = []
    var current:
      (
        number: UInt8, alternate: UInt8, cls: UInt8, sub: UInt8, proto: UInt8,
        declaredEndpoints: UInt8, endpoints: [PassiveUSBDescriptorEndpoint]
      )?
    var totalLength: UInt16?
    var declaredInterfaces: UInt8?
    var companionEligible = false
    var sspCompanionRequired = false
    while offset < bytes.count {
      guard bytes.count - offset >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
      let length = Int(bytes[offset])
      guard length > 0 else { throw PassiveUSBDescriptorBlobError.zeroLength }
      guard offset + length <= bytes.count else {
        throw PassiveUSBDescriptorBlobError.descriptorOverrun
      }
      guard length >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
      let chunk = Array(bytes[offset..<(offset + length)])
      let type = chunk[1]
      descriptors.append(PassiveUSBParsedDescriptor(type: type, bytes: chunk))
      if offset == 0 {
        guard type == 2 else { throw PassiveUSBDescriptorBlobError.missingConfiguration }
      } else if type == 2 {
        throw PassiveUSBDescriptorBlobError.totalLengthMismatch
      }
      if type == 2 {
        guard length == 9, totalLength == nil else {
          throw PassiveUSBDescriptorBlobError.totalLengthMismatch
        }
        totalLength = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
        declaredInterfaces = chunk[4]
        guard totalLength == UInt16(bytes.count) else {
          throw PassiveUSBDescriptorBlobError.totalLengthMismatch
        }
        companionEligible = false
      } else if type == 4 {
        guard length == 9 else { throw PassiveUSBDescriptorBlobError.truncated }
        if let value = current { interfaces.append(makeInterface(value)) }
        let key = (chunk[2], chunk[3])
        guard !interfaces.contains(where: { ($0.number, $0.alternateSetting) == key }) else {
          throw PassiveUSBDescriptorBlobError.duplicateInterfaceOwnership
        }
        current = (chunk[2], chunk[3], chunk[5], chunk[6], chunk[7], chunk[4], [])
        companionEligible = false
      } else if type == 5 {
        guard length == 7, var value = current else {
          throw PassiveUSBDescriptorBlobError.impossibleEndpointOwnership
        }
        let address = chunk[2]
        guard address & 0x70 == 0, address & 0x0F != 0 else {
          throw PassiveUSBDescriptorBlobError.invalidEndpointAddress
        }
        let transfer = chunk[3] & 3
        let attributes = chunk[3]
        let invalidAttributes: Bool =
          switch transfer {
          case 0, 2: attributes & 0xFC != 0
          case 1: attributes & 0xC0 != 0 || attributes & 0x30 == 0x30
          case 3: attributes & 0xC0 != 0 || attributes & 0x30 > 0x10
          default: true
          }
        guard !invalidAttributes else {
          throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
        }
        if transfer == 1 || transfer == 3 {
          guard chunk[6] != 0 else { throw PassiveUSBDescriptorBlobError.invalidInterval }
        }
        if transfer == 1 {
          guard chunk[6] <= 16 else { throw PassiveUSBDescriptorBlobError.invalidInterval }
        }
        if transfer == 3, attributes & 0x30 == 0x10 {
          guard negotiatedSpeed == .superSpeedPlus else {
            throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
          }
        }
        if transfer == 2 || transfer == 1, negotiatedSpeed == .low {
          throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
        }
        if transfer == 3, attributes & 0x30 == 0x10 {
          guard (8...16).contains(chunk[6]) else {
            throw PassiveUSBDescriptorBlobError.invalidInterval
          }
        }
        if negotiatedSpeed != nil {
          if let negotiatedSpeed,
            negotiatedSpeed == .high || negotiatedSpeed == .superSpeed
              || negotiatedSpeed == .superSpeedPlus, transfer == 3 || transfer == 1, chunk[6] > 16
          {
            throw PassiveUSBDescriptorBlobError.invalidInterval
          }
        }
        guard !value.endpoints.contains(where: { $0.address == address }) else {
          throw PassiveUSBDescriptorBlobError.impossibleEndpointOwnership
        }
        let packet = UInt16(chunk[4]) | (UInt16(chunk[5]) << 8)
        value.endpoints.append(
          PassiveUSBDescriptorEndpoint(
            address: address,
            transferType: transfer == 0
              ? "control" : transfer == 1 ? "isochronous" : transfer == 2 ? "bulk" : "interrupt",
            maxPacketSize: packet,
            interval: chunk[6],
            nominalIntervalMicroseconds: nominalIntervalMicroseconds(
              transferType: transfer,
              interval: chunk[6],
              speed: negotiatedSpeed
            ),
            intervalResult: intervalResult(
              transferType: transfer,
              interval: chunk[6],
              speed: negotiatedSpeed
            ),
            superSpeedCompanion: nil,
            superSpeedPlusCompanion: nil
          )
        )
        current = value
        companionEligible = true
      } else if type == 0x30 {
        guard length == 6, var value = current, !value.endpoints.isEmpty else {
          throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor
        }
        guard value.endpoints.last?.superSpeedCompanion == nil else {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        guard companionEligible else {
          throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor
        }
        if let negotiatedSpeed, negotiatedSpeed != .superSpeed && negotiatedSpeed != .superSpeedPlus
        {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        guard let transferName = value.endpoints.last?.transferType else {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        let endpoint = value.endpoints.removeLast()
        try validateSuperSpeedCompanion(chunk: chunk, endpoint: endpoint)
        value.endpoints.append(
          PassiveUSBDescriptorEndpoint(
            address: endpoint.address,
            transferType: endpoint.transferType,
            maxPacketSize: endpoint.maxPacketSize,
            interval: endpoint.interval,
            nominalIntervalMicroseconds: endpoint.nominalIntervalMicroseconds,
            intervalResult: endpoint.intervalResult,
            superSpeedCompanion: PassiveUSBSuperSpeedCompanion(
              maxBurst: chunk[2],
              attributes: chunk[3],
              bytesPerInterval: UInt16(chunk[4]) | (UInt16(chunk[5]) << 8)
            ),
            superSpeedPlusCompanion: nil
          )
        )
        current = value
        companionEligible = false
        sspCompanionRequired = transferName == "isochronous" && (chunk[3] & 0x80) != 0
      } else if type == 0x31 {
        if let negotiatedSpeed, negotiatedSpeed != .superSpeed && negotiatedSpeed != .superSpeedPlus
        {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        guard sspCompanionRequired, length == 8, var value = current, !value.endpoints.isEmpty
        else { throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor }
        guard negotiatedSpeed == .superSpeedPlus else {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        guard let superSpeedPlusContext else {
          throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
        }
        guard value.endpoints.last?.transferType == "isochronous",
          value.endpoints.last?.superSpeedPlusCompanion == nil, chunk[2] == 0, chunk[3] == 0
        else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
        let endpoint = value.endpoints.removeLast()
        let bytes =
          UInt32(chunk[4]) | (UInt32(chunk[5]) << 8) | (UInt32(chunk[6]) << 16)
          | (UInt32(chunk[7]) << 24)
        guard let maximum = superSpeedPlusContext.maximumBytesPerInterval, bytes > 49_152,
          bytes < maximum
        else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
        value.endpoints.append(
          PassiveUSBDescriptorEndpoint(
            address: endpoint.address,
            transferType: endpoint.transferType,
            maxPacketSize: endpoint.maxPacketSize,
            interval: endpoint.interval,
            nominalIntervalMicroseconds: endpoint.nominalIntervalMicroseconds,
            intervalResult: endpoint.intervalResult,
            superSpeedCompanion: endpoint.superSpeedCompanion,
            superSpeedPlusCompanion: PassiveUSBSuperSpeedPlusCompanion(bytesPerInterval: bytes)
          )
        )
        current = value
        sspCompanionRequired = false
      } else {
        companionEligible = false
        if sspCompanionRequired { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      }
      offset += length
    }
    if let value = current { interfaces.append(makeInterface(value)) }
    if sspCompanionRequired { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
    if negotiatedSpeed == .superSpeed || negotiatedSpeed == .superSpeedPlus {
      guard
        interfaces.allSatisfy({ interface in
          interface.endpoints.allSatisfy { endpoint in endpoint.superSpeedCompanion != nil }
        })
      else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
    }
    guard let totalLength, let declaredInterfaces else {
      throw PassiveUSBDescriptorBlobError.missingConfiguration
    }
    guard Set(interfaces.map(\.number)).count == Int(declaredInterfaces) else {
      throw PassiveUSBDescriptorBlobError.totalLengthMismatch
    }
    guard interfaces.allSatisfy({ Int($0.declaredEndpointCount) == $0.endpoints.count }) else {
      throw PassiveUSBDescriptorBlobError.totalLengthMismatch
    }
    return PassiveUSBConfigurationDescriptor(
      totalLength: totalLength,
      declaredInterfaceCount: declaredInterfaces,
      descriptors: descriptors,
      interfaces: interfaces,
      negotiatedSpeed: negotiatedSpeed
    )
  }

  private static func validateSuperSpeedCompanion(
    chunk: [UInt8],
    endpoint: PassiveUSBDescriptorEndpoint
  ) throws {
    guard chunk[2] <= 15 else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
    let attributes = chunk[3]
    let bytesPerInterval = UInt16(chunk[4]) | (UInt16(chunk[5]) << 8)
    let burst = UInt64(chunk[2]) + 1
    let rawPacket = endpoint.maxPacketSize
    let packet = UInt64(rawPacket & 0x07FF)
    guard rawPacket & 0xF800 == 0 else {
      throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
    }
    switch endpoint.transferType {
    case "bulk":
      guard packet == 1_024 else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      guard attributes & 0xE0 == 0, attributes & 0x1F <= 16, bytesPerInterval == 0 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
    case "interrupt":
      guard packet >= 1, packet <= 1_024, chunk[2] == 0 || packet == 1_024 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      let maxBytes = packet.multipliedReportingOverflow(by: burst)
      guard attributes == 0, !maxBytes.overflow, UInt64(bytesPerInterval) <= maxBytes.partialValue
      else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
    case "control":
      guard chunk[2] == 0, packet == 512, attributes == 0, bytesPerInterval == 0 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
    case "isochronous":
      guard packet <= 1_024 else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      guard chunk[2] == 0 || packet == 1_024 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      guard attributes & 0x7C == 0 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      guard attributes & 0x03 <= 2 else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      if chunk[2] == 0, attributes & 0x03 != 0 {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      let mult = UInt64(attributes & 0x03) + 1
      if attributes & 0x80 != 0, bytesPerInterval != 1 {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      let maxBytes = packet.multipliedReportingOverflow(by: burst).partialValue
        .multipliedReportingOverflow(by: mult)
      guard !maxBytes.overflow, UInt64(bytesPerInterval) <= maxBytes.partialValue else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
    default: throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
    }
  }

  private static func makeInterface(
    _ value: (
      number: UInt8, alternate: UInt8, cls: UInt8, sub: UInt8, proto: UInt8,
      declaredEndpoints: UInt8, endpoints: [PassiveUSBDescriptorEndpoint]
    )
  ) -> PassiveUSBDescriptorInterface {
    PassiveUSBDescriptorInterface(
      number: value.number,
      alternateSetting: value.alternate,
      interfaceClass: value.cls,
      interfaceSubclass: value.sub,
      interfaceProtocol: value.proto,
      declaredEndpointCount: value.declaredEndpoints,
      endpoints: value.endpoints
    )
  }

  private static func nominalIntervalMicroseconds(
    transferType: UInt8,
    interval: UInt8,
    speed: PassiveUSBNegotiatedSpeed?
  ) -> UInt64? {
    guard let speed, interval >= 1 else { return nil }
    switch speed {
    case .low: return transferType == 3 ? UInt64(interval) * 1_000 : nil
    case .full:
      if transferType == 3 { return UInt64(interval) * 1_000 }
      if transferType == 1, interval <= 16 { return (UInt64(1) << UInt64(interval - 1)) * 1_000 }
      return nil
    case .high, .superSpeed, .superSpeedPlus:
      guard transferType == 1 || transferType == 3, interval <= 16 else { return nil }
      return (UInt64(1) << UInt64(interval - 1)) * 125
    }
  }

  private static func intervalResult(
    transferType: UInt8,
    interval: UInt8,
    speed: PassiveUSBNegotiatedSpeed?
  ) -> PassiveUSBIntervalResult {
    guard let speed else { return .unsupportedSpeedOrTransfer }
    guard transferType == 1 || transferType == 3 else { return .ignoredNotServiceInterval }
    guard interval > 0 else { return .invalidRange }
    if transferType == 1, interval > 16 { return .invalidRange }
    switch speed {
    case .low:
      return transferType == 3
        ? .validDescriptorNominal(UInt64(interval) * 1_000) : .unsupportedSpeedOrTransfer
    case .full:
      if transferType == 3 { return .validDescriptorNominal(UInt64(interval) * 1_000) }
      return .validDescriptorNominal((UInt64(1) << UInt64(interval - 1)) * 1_000)
    case .high, .superSpeed, .superSpeedPlus:
      guard interval <= 16 else { return .invalidRange }
      return .validDescriptorNominal((UInt64(1) << UInt64(interval - 1)) * 125)
    }
  }
}
