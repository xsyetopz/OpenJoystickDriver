/// The expansion index bits of the GIP flags ([MS-GIPUSB] Table 14).
private let gipExpansionIndexMask: UInt8 = 0x07

extension GIPDriver {
  /// Default: a GIP controller reports no logical connection change.
  public func consumeInputConnectionStateChange() -> ControllerInputConnectionState? { nil }

  /// Share presence varies by model, so only a row with the `shareButton` parameter, whose fixed
  /// offset is the per-record evidence that the model has Share, declares it.
  public var capabilities: ControllerCapabilities {
    PhysicalProtocolID.xboxGIP.describedControls.union(
      ControllerCapabilities(controls: shareButtonFromEnd != nil ? [.capture] : [])
    )
  }

  /// Rumble on all four motors when the row allows physical output; none otherwise.
  public var outputCapabilities: PhysicalControllerOutputCapabilities {
    allowsPhysicalOutput
      ? PhysicalControllerOutputCapabilities(rumbleMotors: [
        .lowFrequency, .highFrequency, .leftTrigger, .rightTrigger,
      ]) : .none
  }

  /// Default: no default color.
  public var defaultColor: ControllerColor? { nil }

  // MARK: - Frame builders and report decoders

  /// Builds the Protocol Control ACK for a GIP packet with the ACME flag set (SDL
  /// `GIP_Acknowledge`): a system message to the packet's expansion index, then the ACK control
  /// code, the acknowledged command and its System flag, the bytes received as a 32-bit offset
  /// and the bytes still to come.
  static func acknowledgementPacket(
    command: UInt8,
    options: UInt8,
    sequence: UInt8,
    received: UInt16,
    remaining: UInt16 = 0
  ) -> [UInt8] {
    let headerFlags = GIPOption.internal | (options & gipExpansionIndexMask)
    return [
      GIPCommand.acknowledge, headerFlags, sequence, 9, 0, command, options & GIPOption.internal,
      UInt8(truncatingIfNeeded: received), UInt8(truncatingIfNeeded: received >> 8), 0, 0,
      UInt8(truncatingIfNeeded: remaining), UInt8(truncatingIfNeeded: remaining >> 8),
    ]
  }

  /// The left trigger, a little-endian 16-bit value at byte 2.
  func parseLT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[2]) | (UInt16(bytes[3]) << 8) }

  /// The right trigger, a little-endian 16-bit value at byte 4.
  func parseRT(from bytes: [UInt8]) -> UInt16 { UInt16(bytes[4]) | (UInt16(bytes[5]) << 8) }

  /// The left stick X and Y and the right stick X and Y, each a little-endian signed 16-bit value
  /// starting at bytes 6, 8, 10 and 12.
  func parseSticks(from bytes: [UInt8]) -> (Int16, Int16, Int16, Int16) {
    let lsx = Int16(bitPattern: UInt16(bytes[6]) | (UInt16(bytes[7]) << 8))
    let lsy = Int16(bitPattern: UInt16(bytes[8]) | (UInt16(bytes[9]) << 8))
    let rsx = Int16(bitPattern: UInt16(bytes[10]) | (UInt16(bytes[11]) << 8))
    let rsy = Int16(bitPattern: UInt16(bytes[12]) | (UInt16(bytes[13]) << 8))
    return (lsx, lsy, rsx, rsy)
  }

  /// The hat direction of the D-pad bits: up 1, down 2, left 4, right 8.
  func mapDpad(_ value: UInt8) -> HatDirection {
    // bits: up=1, down=2, left=4, right=8
    switch value {
    case 1: .north
    case 2: .south
    case 4: .west
    case 8: .east
    case 9: .northEast  // up + right
    case 5: .northWest  // up + left
    case 10: .southEast  // down + right
    case 6: .southWest  // down + left
    default: .neutral
    }
  }
}
