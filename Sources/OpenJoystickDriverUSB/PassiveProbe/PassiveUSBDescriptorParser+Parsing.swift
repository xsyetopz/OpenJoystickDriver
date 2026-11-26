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
      guard Self.fitsSuperSpeedPlus(perInterval, within: superSpeedPlusContext) else {
        throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
      }
      value.endpoints[value.endpoints.count - 1] = endpoint.withCompanions(
        superSpeed: endpoint.superSpeedCompanion,
        superSpeedPlus: PassiveUSBSuperSpeedPlusCompanion(bytesPerInterval: perInterval)
      )
      current = value
      sspCompanionRequired = false
    }

    /// Whether `perInterval` bytes need the SuperSpeedPlus companion, above the 49,152 a
    /// SuperSpeed companion carries, and stay below the maximum the context allows.
    private static func fitsSuperSpeedPlus(
      _ perInterval: UInt32,
      within context: PassiveUSBSuperSpeedPlusValidationContext
    ) -> Bool {
      guard let maximum = context.maximumBytesPerInterval else { return false }
      return perInterval > 49_152 && perInterval < maximum
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
      guard hasValidReservedAttributeBits(transfer: transfer, attributes: attributes) else {
        throw PassiveUSBDescriptorBlobError.invalidTransferAttributes
      }
      guard intervalRange(transfer: transfer).contains(interval) else {
        throw PassiveUSBDescriptorBlobError.invalidInterval
      }
      let isSuperSpeedPlusInterrupt = transfer == 3 && attributes & 0x30 == 0x10
      guard
        speedAllows(transfer: transfer, superSpeedPlusInterrupt: isSuperSpeedPlusInterrupt, speed)
      else { throw PassiveUSBDescriptorBlobError.invalidTransferAttributes }
      let speedRange = intervalRange(
        transfer: transfer,
        superSpeedPlusInterrupt: isSuperSpeedPlusInterrupt,
        speed: speed
      )
      guard speedRange.contains(interval) else {
        throw PassiveUSBDescriptorBlobError.invalidInterval
      }
    }

    /// The intervals `transfer` accepts at any speed: isochronous `1...16`, interrupt nonzero.
    private static func intervalRange(transfer: UInt8) -> ClosedRange<UInt8> {
      switch transfer {
      case 1: 1...16
      case 3: 1...UInt8.max
      default: 0...UInt8.max
      }
    }

    /// Whether `speed` carries `transfer`: a SuperSpeedPlus interrupt only at SuperSpeedPlus, and
    /// isochronous or bulk at any speed but low.
    private static func speedAllows(
      transfer: UInt8,
      superSpeedPlusInterrupt: Bool,
      _ speed: PassiveUSBNegotiatedSpeed?
    ) -> Bool {
      if superSpeedPlusInterrupt { return speed == .superSpeedPlus }
      return !((transfer == 1 || transfer == 2) && speed == .low)
    }

    /// The intervals `speed` allows for `transfer`: `8...16` for a SuperSpeedPlus interrupt, and at
    /// most 16 for a periodic transfer counted in microframes (high speed and above).
    private static func intervalRange(
      transfer: UInt8,
      superSpeedPlusInterrupt: Bool,
      speed: PassiveUSBNegotiatedSpeed?
    ) -> ClosedRange<UInt8> {
      if superSpeedPlusInterrupt { return 8...16 }
      let isPeriodic = transfer == 1 || transfer == 3
      let isMicroframeSpeed = speed == .high || speed == .superSpeed || speed == .superSpeedPlus
      return isPeriodic && isMicroframeSpeed ? 0...16 : 0...UInt8.max
    }

    /// Whether `attributes` leaves clear the bits that `transfer` reserves: every bit above the
    /// type for control and bulk, the high two bits and usage `0b11` for isochronous, and the high
    /// two bits and any usage above `0b01` for interrupt.
    private static func hasValidReservedAttributeBits(transfer: UInt8, attributes: UInt8) -> Bool {
      switch transfer {
      case 0, 2: attributes & 0xFC == 0
      case 1: attributes & 0xC0 == 0 && attributes & 0x30 != 0x30
      case 3: attributes & 0xC0 == 0 && attributes & 0x30 <= 0x10
      default: false
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
    let companion = SuperSpeedCompanionFields(chunk: chunk, maxPacketSize: endpoint.maxPacketSize)
    guard companion.fits(transferType: endpoint.transferType) else {
      throw PassiveUSBDescriptorBlobError.invalidCompanionDescriptor
    }
  }

  /// The fields of a SuperSpeed endpoint companion descriptor and of its endpoint that the USB 3
  /// specification constrains together, per transfer type.
  private struct SuperSpeedCompanionFields {
    /// `bMaxBurst`: bursts after the first.
    let maxBurst: UInt8
    /// `bmAttributes`.
    let attributes: UInt8
    /// `wBytesPerInterval`.
    let bytesPerInterval: UInt64
    /// The endpoint's packet size, bits 10...0 of `wMaxPacketSize`.
    let packet: UInt64
    /// Whether `wMaxPacketSize` sets any of bits 15...11, which SuperSpeed reserves.
    let packetHasReservedBits: Bool

    init(chunk: [UInt8], maxPacketSize: UInt16) {
      maxBurst = chunk[2]
      attributes = chunk[3]
      bytesPerInterval = UInt64(UInt16(chunk[4]) | (UInt16(chunk[5]) << 8))
      packet = UInt64(maxPacketSize & 0x07FF)
      packetHasReservedBits = maxPacketSize & 0xF800 != 0
    }

    /// The packets one service interval carries per burst.
    private var burst: UInt64 { UInt64(maxBurst) + 1 }

    /// Whether the fields are valid for an endpoint of `transferType`.
    func fits(transferType: String) -> Bool {
      guard maxBurst <= 15, !packetHasReservedBits else { return false }
      switch transferType {
      case "bulk": return fitsBulk
      case "interrupt": return fitsInterrupt
      case "control":
        return maxBurst == 0 && packet == 512 && attributes == 0 && bytesPerInterval == 0
      case "isochronous": return fitsIsochronous
      default: return false
      }
    }

    private var fitsBulk: Bool {
      packet == 1_024 && attributes & 0xE0 == 0 && attributes & 0x1F <= 16 && bytesPerInterval == 0
    }

    private var fitsInterrupt: Bool {
      guard (1...1_024).contains(packet), maxBurst == 0 || packet == 1_024, attributes == 0 else {
        return false
      }
      let maxBytes = packet.multipliedReportingOverflow(by: burst)
      return !maxBytes.overflow && bytesPerInterval <= maxBytes.partialValue
    }

    private var fitsIsochronous: Bool {
      let mult = attributes & 0x03
      guard packet <= 1_024, maxBurst == 0 || packet == 1_024, attributes & 0x7C == 0, mult <= 2,
        maxBurst != 0 || mult == 0, attributes & 0x80 == 0 || bytesPerInterval == 1
      else { return false }
      let maxBytes = packet.multipliedReportingOverflow(by: burst).partialValue
        .multipliedReportingOverflow(by: UInt64(mult) + 1)
      return !maxBytes.overflow && bytesPerInterval <= maxBytes.partialValue
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
