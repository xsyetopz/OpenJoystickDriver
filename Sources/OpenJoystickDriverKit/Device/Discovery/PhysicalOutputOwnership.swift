import Foundation

enum PhysicalOutputChannel: Equatable, Hashable, Sendable {
  case rumble(PhysicalRumbleMotor)
  case playerIndicator
  case color
  case brightness
  case adaptiveTrigger(PhysicalAdaptiveTrigger)

  var sortKey: String {
    switch self {
    case .rumble(let motor): "rumble:\(motor.rawValue)"
    case .playerIndicator: "player"
    case .color: "color"
    case .brightness: "brightness"
    case .adaptiveTrigger(let trigger): "adaptive:\(trigger.rawValue)"
    }
  }
}

extension RemappingPhysicalOutput {
  var channel: PhysicalOutputChannel {
    switch self {
    case .rumble(let motor, _): .rumble(motor)
    case .playerIndicator: .playerIndicator
    case .color: .color
    case .brightness: .brightness
    case .adaptiveTrigger(let trigger, _): .adaptiveTrigger(trigger)
    }
  }

  var isNeutral: Bool {
    switch self {
    case .rumble(_, let intensity), .brightness(let intensity): intensity == 0
    case .playerIndicator(let indicator): indicator == .off
    case .color(let red, let green, let blue): red == 0 && green == 0 && blue == 0
    case .adaptiveTrigger(_, let effect): effect.kind == .off
    }
  }
}

struct PhysicalOutputOwnership {
  private struct Claim: Sendable {
    let output: RemappingPhysicalOutput
    let sequence: UInt64
  }

  private var nextSequence: UInt64 = 0
  private var mappingClaims: [DeviceIdentifier: [PhysicalOutputChannel: [UUID: Claim]]] = [:]
  private var manualOverrides:
    [DeviceIdentifier: [PhysicalOutputChannel: RemappingPhysicalOutput]] = [:]

  var mappingClaimCount: Int {
    mappingClaims.values.reduce(0) { deviceTotal, channels in
      deviceTotal + channels.values.reduce(0) { $0 + $1.count }
    }
  }

  @discardableResult mutating func setMapping(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: DeviceIdentifier
  ) -> PhysicalOutputChannel {
    let channel = output.channel
    if active {
      nextSequence &+= 1
      mappingClaims[identifier, default: [:]][channel, default: [:]][owner] = Claim(
        output: output,
        sequence: nextSequence
      )
    } else {
      mappingClaims[identifier]?[channel]?.removeValue(forKey: owner)
      removeEmptyMappingStorage(for: identifier, channel: channel)
    }
    return channel
  }

  mutating func releaseMappings(for identifier: DeviceIdentifier) -> Set<PhysicalOutputChannel> {
    guard let claims = mappingClaims.removeValue(forKey: identifier) else { return [] }
    return Set(claims.keys)
  }

  @discardableResult mutating func setManual(
    _ output: RemappingPhysicalOutput,
    for identifier: DeviceIdentifier
  ) -> PhysicalOutputChannel {
    let channel = output.channel
    if output.isNeutral {
      manualOverrides[identifier]?[channel] = nil
      if manualOverrides[identifier]?.isEmpty == true {
        manualOverrides[identifier] = nil
      }
    } else {
      manualOverrides[identifier, default: [:]][channel] = output
    }
    return channel
  }

  mutating func releaseManualRumble(for identifier: DeviceIdentifier)
    -> Set<PhysicalOutputChannel>
  {
    let existingChannels = manualOverrides[identifier].map { Array($0.keys) } ?? []
    let channels = Set(
      existingChannels.filter {
        if case .rumble = $0 { return true }
        return false
      }
    )
    for channel in channels { manualOverrides[identifier]?[channel] = nil }
    if manualOverrides[identifier]?.isEmpty == true { manualOverrides[identifier] = nil }
    return channels
  }

  func effectiveOutput(
    for channel: PhysicalOutputChannel,
    device identifier: DeviceIdentifier
  ) -> RemappingPhysicalOutput? {
    if let manual = manualOverrides[identifier]?[channel] { return manual }
    return mappingClaims[identifier]?[channel]?.values.max { lhs, rhs in
      lhs.sequence < rhs.sequence
    }?.output
  }

  mutating func removeDevice(_ identifier: DeviceIdentifier) {
    mappingClaims[identifier] = nil
    manualOverrides[identifier] = nil
  }

  mutating func removeAll() {
    mappingClaims.removeAll()
    manualOverrides.removeAll()
  }

  private mutating func removeEmptyMappingStorage(
    for identifier: DeviceIdentifier,
    channel: PhysicalOutputChannel
  ) {
    if mappingClaims[identifier]?[channel]?.isEmpty == true {
      mappingClaims[identifier]?[channel] = nil
    }
    if mappingClaims[identifier]?.isEmpty == true { mappingClaims[identifier] = nil }
  }
}
