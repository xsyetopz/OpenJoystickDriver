import Foundation

/// A physical output of a controller that claims compete for: one rumble motor, the player
/// indicator, the color, the brightness or one adaptive trigger.
enum PhysicalOutputChannel: Equatable, Hashable, Sendable {
  /// One rumble motor.
  case rumble(PhysicalRumbleMotor)
  /// The player indicator.
  case playerIndicator
  /// The lighting color.
  case color
  /// The lighting brightness.
  case brightness
  /// One adaptive trigger.
  case adaptiveTrigger(PhysicalAdaptiveTrigger)

  /// A stable text key that orders channels.
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
  /// The channel that this output drives.
  var channel: PhysicalOutputChannel {
    switch self {
    case .rumble(let motor, _): .rumble(motor)
    case .playerIndicator: .playerIndicator
    case .color: .color
    case .brightness: .brightness
    case .adaptiveTrigger(let trigger, _): .adaptiveTrigger(trigger)
    }
  }

  /// Whether this output is the neutral one: zero rumble or brightness intensity, an off player
  /// indicator, black, or an off adaptive trigger.
  var isNeutral: Bool {
    switch self {
    case .rumble(_, let intensity), .brightness(let intensity): intensity == 0
    case .playerIndicator(let indicator): indicator == .off
    case .color(let color): color == ControllerColor(red: 0, green: 0, blue: 0)
    case .adaptiveTrigger(_, let effect): effect.kind == .off
    }
  }
}

/// The claims on the physical output channels of each controller, resolved to the effective output
/// of a channel.
///
/// A color preview wins over a manual claim, a manual claim over a mapping claim, and the profile
/// color is the baseline of the color channel only.
struct PhysicalOutputOwnership {
  /// One request for an output, ordered by its sequence.
  struct Claim: Sendable {
    /// The requested output.
    let output: RemappingPhysicalOutput
    /// The order in which claims are made; a greater number is newer.
    let sequence: UInt64
  }

  /// The sequence of the latest claim.
  private var nextSequence: UInt64 = 0
  /// The mapping claims of the remapping layer, by controller, channel and owner.
  private var mappingClaims: [LogicalControllerID: [PhysicalOutputChannel: [UUID: Claim]]] = [:]
  /// Each channel's manual claims, oldest first: the newest wins, a failed command withdraws only
  /// its own, and a delivered one drops the older ones it replaced.
  private var manualClaims: [LogicalControllerID: [PhysicalOutputChannel: [Claim]]] = [:]
  /// The color previews by controller and preview token, which win over every other color claim.
  private var temporaryColorPreviews: [LogicalControllerID: [UUID: Claim]] = [:]
  /// The profile color of each controller, which the color channel falls back to.
  private var profileBaselines: [LogicalControllerID: RemappingPhysicalOutput] = [:]
  /// Counts the clearings of each controller's claims and of all claims, so a state captured
  /// before a clearing (neutralization, disconnect, teardown) is never restored after it.
  private var deviceClearings: [LogicalControllerID: UInt64] = [:]
  /// Counts the clearings of all claims.
  private var allClearings: UInt64 = 0

  /// The number of mapping claims over all controllers and channels.
  var mappingClaimCount: Int {
    mappingClaims.values.reduce(0) { deviceTotal, channels in
      deviceTotal + channels.values.reduce(0) { $0 + $1.count }
    }
  }

  /// Sets the mapping claim of `owner` on the channel of `output` when `active`, and removes it
  /// otherwise.
  ///
  /// - Returns: The channel of `output`.
  @discardableResult
  mutating func setMapping(
    _ output: RemappingPhysicalOutput,
    active: Bool,
    owner: UUID,
    for identifier: LogicalControllerID
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

  /// Removes every mapping claim of `identifier`.
  ///
  /// - Returns: The channels that held one.
  mutating func releaseMappings(for identifier: LogicalControllerID) -> Set<PhysicalOutputChannel> {
    guard let claims = mappingClaims.removeValue(forKey: identifier) else { return [] }
    return Set(claims.keys)
  }

  /// Adds one command's manual claims under one sequence and returns it, for `commitManual` or
  /// `withdrawManual` once the command's write finishes.
  ///
  /// A neutral claim lets mapping claims show through, except a color, where black is a real
  /// claim.
  @discardableResult
  mutating func setManual(
    _ outputs: [RemappingPhysicalOutput],
    for identifier: LogicalControllerID
  ) -> UInt64 {
    nextSequence &+= 1
    for output in outputs {
      manualClaims[identifier, default: [:]][output.channel, default: []].append(
        Claim(output: output, sequence: nextSequence)
      )
    }
    return nextSequence
  }

  /// Adds `output` as one manual claim under a sequence and returns it.
  @discardableResult
  mutating func setManual(
    _ output: RemappingPhysicalOutput,
    for identifier: LogicalControllerID
  ) -> UInt64 { setManual([output], for: identifier) }

  /// Drops the claims older than the delivered claim `sequence` on `channels`.
  mutating func commitManual(
    _ sequence: UInt64,
    on channels: Set<PhysicalOutputChannel>,
    for identifier: LogicalControllerID
  ) {
    for channel in channels
    where manualClaims[identifier]?[channel]?.contains(where: { $0.sequence == sequence }) == true {
      manualClaims[identifier]?[channel]?.removeAll { $0.sequence < sequence }
    }
  }

  /// Removes the failed claim `sequence` from `channels`, and returns whether it was the newest
  /// claim on any of them, so the channel's effective output may have changed.
  mutating func withdrawManual(
    _ sequence: UInt64,
    on channels: Set<PhysicalOutputChannel>,
    for identifier: LogicalControllerID
  ) -> Bool {
    var wasNewest = false
    for channel in channels {
      guard let claims = manualClaims[identifier]?[channel],
        let index = claims.firstIndex(where: { $0.sequence == sequence })
      else { continue }
      if index == claims.count - 1 { wasNewest = true }
      manualClaims[identifier]?[channel]?.remove(at: index)
      removeEmptyManualStorage(for: identifier, channel: channel)
    }
    return wasNewest
  }

  /// Sets the color preview claim of `token`, which wins over every other color claim.
  mutating func setTemporaryColor(
    _ output: RemappingPhysicalOutput,
    token: UUID,
    for identifier: LogicalControllerID
  ) {
    nextSequence &+= 1
    temporaryColorPreviews[identifier, default: [:]][token] = Claim(
      output: output,
      sequence: nextSequence
    )
  }

  /// Removes the color preview claim of `token`.
  mutating func releaseTemporaryColor(token: UUID, for identifier: LogicalControllerID) {
    temporaryColorPreviews[identifier]?[token] = nil
    if temporaryColorPreviews[identifier]?.isEmpty == true {
      temporaryColorPreviews[identifier] = nil
    }
  }

  /// Sets the profile color that the color channel falls back to; nil removes it.
  mutating func setProfileColor(
    _ output: RemappingPhysicalOutput?,
    for identifier: LogicalControllerID
  ) { profileBaselines[identifier] = output }

  /// Removes every manual rumble claim of `identifier`.
  ///
  /// - Returns: The channels that held one.
  mutating func releaseManualRumble(
    for identifier: LogicalControllerID
  ) -> Set<PhysicalOutputChannel> {
    let existingChannels = manualClaims[identifier].map { Array($0.keys) } ?? []
    let channels = Set(
      existingChannels.filter {
        if case .rumble = $0 { return true }
        return false
      }
    )
    for channel in channels {
      manualClaims[identifier]?[channel] = nil
      removeEmptyManualStorage(for: identifier, channel: channel)
    }
    return channels
  }

  /// The output that wins on `channel` of `identifier`, or nil when nothing claims it.
  ///
  /// A color preview wins first, then the newest manual claim, which counts only when it is not
  /// neutral unless the channel is the color, then the newest mapping claim, then the profile
  /// color.
  func effectiveOutput(
    for channel: PhysicalOutputChannel,
    device identifier: LogicalControllerID
  ) -> RemappingPhysicalOutput? {
    if channel == .color,
      let preview = temporaryColorPreviews[identifier]?.values.max(by: { $0.sequence < $1.sequence }
      )
    {
      return preview.output
    }
    if let manual = manualClaims[identifier]?[channel]?.last?.output,
      channel == .color || !manual.isNeutral
    {
      return manual
    }
    if let mapping = mappingClaims[identifier]?[channel]?.values.max(by: { lhs, rhs in
      lhs.sequence < rhs.sequence
    })?.output {
      return mapping
    }
    return channel == .color ? profileBaselines[identifier] : nil
  }

  /// Mapping claims, color previews and the profile color on some channels of one controller, so
  /// a failed mapping or preview write rolls back only what it changed.
  ///
  /// Manual claims are not part of it: a failed manual command withdraws its own claim instead.
  struct ChannelState {
    /// The controller.
    let identifier: LogicalControllerID
    /// The clearing count when the state was captured.
    let clearing: UInt64
    /// The mapping claims on `channels`.
    let mappingClaims: [PhysicalOutputChannel: [UUID: Claim]]
    /// The color previews of the controller.
    let colorPreviews: [UUID: Claim]?
    /// The profile color of the controller.
    let profileBaseline: RemappingPhysicalOutput?
    /// The channels that the state covers.
    let channels: Set<PhysicalOutputChannel>
  }

  /// Captures the mapping claims on `channels`, with the color previews and the profile color, of
  /// `identifier`.
  func state(
    of channels: Set<PhysicalOutputChannel>,
    for identifier: LogicalControllerID
  ) -> ChannelState {
    ChannelState(
      identifier: identifier,
      clearing: clearing(of: identifier),
      mappingClaims: (mappingClaims[identifier] ?? [:]).filter { channels.contains($0.key) },
      colorPreviews: temporaryColorPreviews[identifier],
      profileBaseline: profileBaselines[identifier],
      channels: channels
    )
  }

  /// Restores `state` unless the controller's claims were cleared since it was captured.
  mutating func restore(_ state: ChannelState) {
    let identifier = state.identifier
    guard clearing(of: identifier) == state.clearing else { return }
    for channel in state.channels {
      mappingClaims[identifier, default: [:]][channel] = state.mappingClaims[channel]
      removeEmptyMappingStorage(for: identifier, channel: channel)
    }
    if state.channels.contains(.color) {
      temporaryColorPreviews[identifier] = state.colorPreviews
      profileBaselines[identifier] = state.profileBaseline
    }
  }

  /// Removes every claim of `identifier` and counts the clearing.
  mutating func removeDevice(_ identifier: LogicalControllerID) {
    deviceClearings[identifier, default: 0] &+= 1
    mappingClaims[identifier] = nil
    manualClaims[identifier] = nil
    temporaryColorPreviews[identifier] = nil
    profileBaselines[identifier] = nil
  }

  /// Removes every claim of every controller and counts the clearing.
  mutating func removeAll() {
    allClearings &+= 1
    mappingClaims.removeAll()
    manualClaims.removeAll()
    temporaryColorPreviews.removeAll()
    profileBaselines.removeAll()
  }

  /// The number of clearings that affect `identifier`: its own plus those of all claims.
  private func clearing(of identifier: LogicalControllerID) -> UInt64 {
    (deviceClearings[identifier] ?? 0) &+ allClearings
  }

  /// Removes the empty mapping storage of `channel`, and of `identifier` when nothing else is left.
  private mutating func removeEmptyMappingStorage(
    for identifier: LogicalControllerID,
    channel: PhysicalOutputChannel
  ) {
    if mappingClaims[identifier]?[channel]?.isEmpty == true {
      mappingClaims[identifier]?[channel] = nil
    }
    if mappingClaims[identifier]?.isEmpty == true { mappingClaims[identifier] = nil }
  }

  /// Removes the empty manual storage of `channel`, and of `identifier` when nothing else is left.
  private mutating func removeEmptyManualStorage(
    for identifier: LogicalControllerID,
    channel: PhysicalOutputChannel
  ) {
    if manualClaims[identifier]?[channel]?.isEmpty == true {
      manualClaims[identifier]?[channel] = nil
    }
    if manualClaims[identifier]?.isEmpty == true { manualClaims[identifier] = nil }
  }
}
