public import Foundation

/// A profile moved to another controller model: what the target keeps and what it lacks.
///
/// The conversion builds a new profile and leaves the original alone.
public struct RemappingProfileConversion: Equatable, Sendable {
  /// One part of the profile that the target cannot take.
  public struct LeftOut: Equatable, Sendable {
    /// The kind of part.
    public enum Section: String, CaseIterable, Codable, Sendable {
      /// A base-layer binding.
      case binding = "Binding"
      /// A chord.
      case chord = "Chord"
      /// A sequence.
      case sequence = "Sequence"
      /// A layer, with everything in it.
      case layer = "Layer"
      /// An advanced stick mapping.
      case stickMapping = "StickMapping"
      /// A dual-stage trigger mapping.
      case triggerMapping = "TriggerMapping"
      /// A touch mapping.
      case touchMapping = "TouchMapping"
      /// The gyro output.
      case gyroOutput = "GyroOutput"
      /// The pointer speed.
      case pointerSpeed = "PointerSpeed"
      /// The Joy-Con pair settings.
      case joyConPair = "JoyConPair"
    }

    /// The kind of part.
    public let section: Section
    /// The sources of the part that the target lacks; empty when the cause is not one source, such
    /// as a missing motion sensor.
    public let sources: [RemappingSource]

    /// Creates an entry.
    public init(section: Section, sources: [RemappingSource]) {
      self.section = section
      self.sources = sources
    }
  }

  /// The profile for the target, with a new identity.
  public let profile: RemappingProfile
  /// Each part left out, in profile order.
  public let leftOut: [LeftOut]

  /// Converts `profile` for the controller `device`, which reports `capabilities`.
  ///
  /// Application scope, output policy, color, tuning, macros, and every part whose sources the
  /// target has carry over. The unit of the source device does not: the result applies to the
  /// model.
  public init(
    converting profile: RemappingProfile,
    to device: RemappingDeviceScope,
    name: String,
    capabilities: ControllerProfileCapabilities,
    id: UUID = UUID()
  ) {
    var omitted: [LeftOut] = []
    func keep<Item>(
      _ items: [Item],
      _ section: LeftOut.Section,
      sources: (Item) -> [RemappingSource]
    ) -> [Item] {
      items.filter { item in
        let missing = sources(item).filter { !$0.isAvailable(on: capabilities) }
        if !missing.isEmpty { omitted.append(LeftOut(section: section, sources: missing)) }
        return missing.isEmpty
      }
    }
    func keepWhole(_ section: LeftOut.Section, _ available: Bool, _ axis: RemappingAxis) -> Bool {
      if !available { omitted.append(LeftOut(section: section, sources: [.axis(axis)])) }
      return available
    }

    let bindings = keep(profile.bindings, .binding) { [$0.source] }
    let chords = keep(profile.chords, .chord) { Array($0.sources) }
    let sequences = keep(profile.sequences, .sequence) { $0.sources }
    let layers = keep(profile.layers, .layer) { layer in
      [layer.activator] + layer.bindings.map(\.source) + layer.chords.flatMap { Array($0.sources) }
        + layer.sequences.flatMap(\.sources)
    }
    let stickMappings = profile.stickMappings.filter {
      keepWhole(
        .stickMapping,
        capabilities.physicalInput.controls.isSuperset(of: $0.source.controls),
        $0.source.axis
      )
    }
    let triggerMappings = profile.triggerMappings.filter {
      keepWhole(
        .triggerMapping,
        capabilities.physicalInput.controls.contains($0.source.axis.control),
        $0.source.axis
      )
    }
    let touchMappings = keep(profile.touchMappings, .touchMapping) { [.touchContact($0.surface)] }

    let gyroSources = [profile.gyroOutput.activationSource, profile.gyroOutput.trackball?.source]
      .compactMap { $0 }
    let gyroMissing = gyroSources.filter { !$0.isAvailable(on: capabilities) }
    var gyroOutput = profile.gyroOutput
    if profile.gyroOutput != .default, !capabilities.physicalInput.motion || !gyroMissing.isEmpty {
      omitted.append(LeftOut(section: .gyroOutput, sources: gyroMissing))
      gyroOutput = .default
    }

    var pointerSpeed = profile.pointerSpeed
    if let speed = pointerSpeed, !speed.isSupported(by: capabilities) {
      omitted.append(LeftOut(section: .pointerSpeed, sources: []))
      pointerSpeed = nil
    }
    if profile.joyConPair != nil { omitted.append(LeftOut(section: .joyConPair, sources: [])) }

    self.leftOut = omitted
    self.profile = RemappingProfile(
      id: id,
      name: name,
      device: RemappingDeviceScope(vendorID: device.vendorID, productID: device.productID),
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      physicalColor: profile.physicalColor,
      motionTuning: profile.motionTuning,
      gyroOutput: gyroOutput,
      joyConPair: nil,
      pointerSpeed: pointerSpeed,
      stickMappings: stickMappings,
      triggerMappings: triggerMappings,
      touchMappings: touchMappings,
      bindings: bindings,
      chords: chords,
      sequences: sequences,
      layers: layers,
      macros: profile.macros
    )
  }
}

extension RemappingStickSource {
  fileprivate var axis: RemappingAxis { self == .left ? .leftStickX : .rightStickX }

  fileprivate var controls: Set<Control> {
    self == .left ? [.leftStickX, .leftStickY] : [.rightStickX, .rightStickY]
  }
}

extension RemappingSource {
  /// Whether a controller with `capabilities` reports what this source reads.
  fileprivate func isAvailable(on capabilities: ControllerProfileCapabilities) -> Bool {
    let input = capabilities.physicalInput
    let surfaces = input.touchSurfaces.map(RemappingTouchSurface.init)
    return switch self {
    case .button(let control): input.controls.contains(control)
    case .dpad(let direction): input.controls.contains(direction.control)
    case .axis(let axis), .axisDirection(let axis, _): input.controls.contains(axis.control)
    case .triggerStage(let trigger, _): input.controls.contains(trigger.axis.control)
    case .triggerBand(let band): input.controls.contains(band.trigger.axis.control)
    case .stickRegion(let region): input.controls.isSuperset(of: region.stick.controls)
    case .motionLean: input.motion
    case .touchContact(let surface): surfaces.contains(surface)
    case .touchGrid(let grid): surfaces.contains(grid.surface)
    case .touchSwipe(let swipe): surfaces.contains(swipe.surface)
    case .touchArea(let area): surfaces.contains(area.surface)
    }
  }
}

extension RemappingDpadDirection {
  fileprivate var control: Control {
    switch self {
    case .up: .dpadUp
    case .down: .dpadDown
    case .left: .dpadLeft
    case .right: .dpadRight
    }
  }
}
