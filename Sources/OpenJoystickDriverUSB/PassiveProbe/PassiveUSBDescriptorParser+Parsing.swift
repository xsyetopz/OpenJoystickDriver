import Foundation

extension PassiveUSBConfigurationDescriptorParser {

  /// Parses a configuration descriptor blob and checks its structure.
  ///
  /// `negotiatedSpeed` and `superSpeedPlusContext` tighten the checks of intervals and companion
  /// descriptors.
  ///
  /// - Throws: ``PassiveUSBDescriptorBlobError`` for the first structure rule that the blob breaks.
  public static func parse(
    _ bytes: [UInt8],
    negotiatedSpeed: PassiveUSBNegotiatedSpeed? = nil,
    superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext? = nil
  ) throws -> PassiveUSBConfigurationDescriptor {
    guard !bytes.isEmpty, bytes.count <= maxBlobSize else {
      throw PassiveUSBDescriptorBlobError.unsafeSize
    }
    guard bytes.count >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
    var walk = DescriptorWalk(
      blobLength: bytes.count,
      speed: negotiatedSpeed,
      superSpeedPlusContext: superSpeedPlusContext
    )
    var offset = 0
    while offset < bytes.count {
      guard bytes.count - offset >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
      let length = Int(bytes[offset])
      guard length > 0 else { throw PassiveUSBDescriptorBlobError.zeroLength }
      guard offset + length <= bytes.count else {
        throw PassiveUSBDescriptorBlobError.descriptorOverrun
      }
      guard length >= 2 else { throw PassiveUSBDescriptorBlobError.truncated }
      try walk.read(Array(bytes[offset..<(offset + length)]), isFirst: offset == 0)
      offset += length
    }
    return try walk.finish()
  }

  /// The interface whose endpoint descriptors the walk is collecting.
  private struct OpenInterface {
    let number: UInt8
    let alternate: UInt8
    let interfaceClass: UInt8
    let interfaceSubclass: UInt8
    let interfaceProtocol: UInt8
    let declaredEndpoints: UInt8
    var endpoints: [PassiveUSBDescriptorEndpoint] = []

    var descriptor: PassiveUSBDescriptorInterface {
      PassiveUSBDescriptorInterface(
        number: number,
        alternateSetting: alternate,
        interfaceClass: interfaceClass,
        interfaceSubclass: interfaceSubclass,
        interfaceProtocol: interfaceProtocol,
        declaredEndpointCount: declaredEndpoints,
        endpoints: endpoints
      )
    }
  }

  /// The parser state carried from one descriptor of a configuration blob to the next.
  ///
  /// Each `read` method checks one descriptor type and throws the first rule it breaks, in the
  /// order the USB structure checks apply.
  private struct DescriptorWalk {
    let blobLength: Int
    let speed: PassiveUSBNegotiatedSpeed?
    let superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext?
    var descriptors: [PassiveUSBParsedDescriptor] = []
    var interfaces: [PassiveUSBDescriptorInterface] = []
    var current: OpenInterface?
    var totalLength: UInt16?
    var declaredInterfaces: UInt8?
    /// A SuperSpeed companion may follow only directly after an endpoint descriptor.
    var companionEligible = false
    /// An isochronous companion with bit 7 set requires a SuperSpeedPlus companion next.
    var sspCompanionRequired = false

    init(
      blobLength: Int,
      speed: PassiveUSBNegotiatedSpeed?,
      superSpeedPlusContext: PassiveUSBSuperSpeedPlusValidationContext?
    ) {
      self.blobLength = blobLength
      self.speed = speed
      self.superSpeedPlusContext = superSpeedPlusContext
    }

    private var isSuperSpeedFamily: Bool { speed == .superSpeed || speed == .superSpeedPlus }

    mutating func read(_ chunk: [UInt8], isFirst: Bool) throws {
      let type = chunk[1]
      descriptors.append(PassiveUSBParsedDescriptor(type: type, bytes: chunk))
      if isFirst {
        guard type == 2 else { throw PassiveUSBDescriptorBlobError.missingConfiguration }
      } else if type == 2 {
        throw PassiveUSBDescriptorBlobError.totalLengthMismatch
      }
      switch type {
      case 2: try readConfiguration(chunk)
      case 4: try readInterface(chunk)
      case 5: try readEndpoint(chunk)
      case 0x30: try readSuperSpeedCompanion(chunk)
      case 0x31: try readSuperSpeedPlusCompanion(chunk)
      default:
        companionEligible = false
        if sspCompanionRequired { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      }
    }

    private mutating func readConfiguration(_ chunk: [UInt8]) throws {
      guard chunk.count == 9, totalLength == nil else {
        throw PassiveUSBDescriptorBlobError.totalLengthMismatch
      }
      let declaredLength = UInt16(chunk[2]) | (UInt16(chunk[3]) << 8)
      totalLength = declaredLength
      declaredInterfaces = chunk[4]
      guard declaredLength == UInt16(blobLength) else {
        throw PassiveUSBDescriptorBlobError.totalLengthMismatch
      }
      companionEligible = false
    }

    private mutating func readInterface(_ chunk: [UInt8]) throws {
      guard chunk.count == 9 else { throw PassiveUSBDescriptorBlobError.truncated }
      if let current { interfaces.append(current.descriptor) }
      let key = (chunk[2], chunk[3])
      guard !interfaces.contains(where: { ($0.number, $0.alternateSetting) == key }) else {
        throw PassiveUSBDescriptorBlobError.duplicateInterfaceOwnership
      }
      current = OpenInterface(
        number: chunk[2],
        alternate: chunk[3],
        interfaceClass: chunk[5],
        interfaceSubclass: chunk[6],
        interfaceProtocol: chunk[7],
        declaredEndpoints: chunk[4]
      )
      companionEligible = false
    }

    private mutating func readEndpoint(_ chunk: [UInt8]) throws {
      guard chunk.count == 7, var value = current else {
        throw PassiveUSBDescriptorBlobError.impossibleEndpointOwnership
      }
      let address = chunk[2]
      guard address & 0x70 == 0, address & 0x0F != 0 else {
        throw PassiveUSBDescriptorBlobError.invalidEndpointAddress
      }
      let attributes = chunk[3]
      let transfer = attributes & 3
      let interval = chunk[6]
      try Self.validateEndpoint(
        transfer: transfer,
        attributes: attributes,
        interval: interval,
        speed: speed
      )
      guard !value.endpoints.contains(where: { $0.address == address }) else {
        throw PassiveUSBDescriptorBlobError.impossibleEndpointOwnership
      }
      value.endpoints.append(
        PassiveUSBDescriptorEndpoint(
          address: address,
          transferType: Self.transferName(transfer),
          maxPacketSize: UInt16(chunk[4]) | (UInt16(chunk[5]) << 8),
          interval: interval,
          nominalIntervalMicroseconds:
            PassiveUSBConfigurationDescriptorParser.nominalIntervalMicroseconds(
              transferType: transfer,
              interval: interval,
              speed: speed
            ),
          intervalResult: PassiveUSBConfigurationDescriptorParser.intervalResult(
            transferType: transfer,
            interval: interval,
            speed: speed
          ),
          superSpeedCompanion: nil,
          superSpeedPlusCompanion: nil
        )
      )
      current = value
      companionEligible = true
    }

    private mutating func readSuperSpeedCompanion(_ chunk: [UInt8]) throws {
      guard chunk.count == 6, var value = current, let endpoint = value.endpoints.last else {
        throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor
      }
      guard endpoint.superSpeedCompanion == nil else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      guard companionEligible else {
        throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor
      }
      if speed != nil, !isSuperSpeedFamily {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      try PassiveUSBConfigurationDescriptorParser.validateSuperSpeedCompanion(
        chunk: chunk,
        endpoint: endpoint
      )
      value.endpoints[value.endpoints.count - 1] = endpoint.withCompanions(
        superSpeed: PassiveUSBSuperSpeedCompanion(
          maxBurst: chunk[2],
          attributes: chunk[3],
          bytesPerInterval: UInt16(chunk[4]) | (UInt16(chunk[5]) << 8)
        ),
        superSpeedPlus: nil
      )
      current = value
      companionEligible = false
      sspCompanionRequired = endpoint.transferType == "isochronous" && (chunk[3] & 0x80) != 0
    }

    private mutating func readSuperSpeedPlusCompanion(_ chunk: [UInt8]) throws {
      if speed != nil, !isSuperSpeedFamily {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      guard sspCompanionRequired, chunk.count == 8, var value = current,
        let endpoint = value.endpoints.last
      else { throw PassiveUSBDescriptorBlobError.orphanCompanionDescriptor }
      guard speed == .superSpeedPlus, let superSpeedPlusContext else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      guard endpoint.transferType == "isochronous", endpoint.superSpeedPlusCompanion == nil,
        chunk[2] == 0, chunk[3] == 0
      else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      let perInterval =
        UInt32(chunk[4]) | (UInt32(chunk[5]) << 8) | (UInt32(chunk[6]) << 16)
        | (UInt32(chunk[7]) << 24)
      guard let maximum = superSpeedPlusContext.maximumBytesPerInterval, perInterval > 49_152,
        perInterval < maximum
      else { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      value.endpoints[value.endpoints.count - 1] = endpoint.withCompanions(
        superSpeed: endpoint.superSpeedCompanion,
        superSpeedPlus: PassiveUSBSuperSpeedPlusCompanion(bytesPerInterval: perInterval)
      )
      current = value
      sspCompanionRequired = false
    }

    /// Closes the last interface and checks the counts the configuration descriptor declared.
    mutating func finish() throws -> PassiveUSBConfigurationDescriptor {
      if let current { interfaces.append(current.descriptor) }
      if sspCompanionRequired { throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor }
      if isSuperSpeedFamily {
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
        negotiatedSpeed: speed
      )
    }

    /// Checks the transfer attributes and interval of an endpoint for the negotiated `speed`.
    ///
    /// `transfer` is 0 control, 1 isochronous, 2 bulk, or 3 interrupt.
    private static func validateEndpoint(
      transfer: UInt8,
      attributes: UInt8,
      interval: UInt8,
      speed: PassiveUSBNegotiatedSpeed?
    ) throws {
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
      let isPeriodic = transfer == 1 || transfer == 3
      if isPeriodic, interval == 0 { throw PassiveUSBDescriptorBlobError.invalidInterval }
      if transfer == 1, interval > 16 { throw PassiveUSBDescriptorBlobError.invalidInterval }
      let isSuperSpeedPlusInterrupt = transfer == 3 && attributes & 0x30 == 0x10
      if isSuperSpeedPlusInterrupt, speed != .superSpeedPlus {
        throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
      }
      if transfer == 2 || transfer == 1, speed == .low {
        throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
      }
      if isSuperSpeedPlusInterrupt, !(8...16).contains(interval) {
        throw PassiveUSBDescriptorBlobError.invalidInterval
      }
      let isMicroframeSpeed = speed == .high || speed == .superSpeed || speed == .superSpeedPlus
      if isMicroframeSpeed, isPeriodic, interval > 16 {
        throw PassiveUSBDescriptorBlobError.invalidInterval
      }
    }

    private static func transferName(_ transfer: UInt8) -> String {
      switch transfer {
      case 0: "control"
      case 1: "isochronous"
      case 2: "bulk"
      default: "interrupt"
      }
    }
  }

  /// Checks the SuperSpeed companion descriptor `chunk` against its `endpoint`.
  ///
  /// - Throws: ``PassiveUSBDescriptorBlobError/invalidCompanionDescriptor`` when it does not fit.
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
}

extension PassiveUSBDescriptorEndpoint {
  /// Returns this endpoint with its companion descriptors replaced.
  fileprivate func withCompanions(
    superSpeed: PassiveUSBSuperSpeedCompanion?,
    superSpeedPlus: PassiveUSBSuperSpeedPlusCompanion?
  ) -> PassiveUSBDescriptorEndpoint {
    PassiveUSBDescriptorEndpoint(
      address: address,
      transferType: transferType,
      maxPacketSize: maxPacketSize,
      interval: interval,
      nominalIntervalMicroseconds: nominalIntervalMicroseconds,
      intervalResult: intervalResult,
      superSpeedCompanion: superSpeed,
      superSpeedPlusCompanion: superSpeedPlus
    )
  }
}
