import Foundation
import OpenJoystickDriverKit

struct DestinationOption: Hashable {
  let destination: RemappingDestination
  let title: String

  static func options(
    for source: RemappingSource,
    including current: RemappingDestination? = nil
  ) -> [Self] {
    var options = all.filter { isCompatible($0.destination, with: source) }
    if let current, isCompatible(current, with: source),
      !options.contains(where: { $0.destination == current })
    {
      options.append(
        Self(destination: current, title: RuntimePresentation.destinationLabel(current))
      )
    }
    return options
  }

  static let all: [Self] = {
    // Keep the ordinary keyboard destination first so source changes can fall back to a useful,
    // conventional choice instead of an arbitrary enum ordering.  Modifier combinations are
    // limited to arrow and function keys; capture can still preserve any custom destination.
    let keyboardKeys =
      [RemappingKeyboardKey.space] + RemappingKeyboardKey.allCases.filter { $0 != .space }
    let plainKeyboard = keyboardKeys.map { key in
      RemappingDestination.keyboard(key: key, modifiers: [])
    }
    let modifierGroups: [Set<RemappingKeyModifier>] =
      [[.command], [.control], [.option], [.shift]] + [
        [.command, .control], [.command, .option], [.command, .shift],
      ] + [[.control, .option], [.control, .shift], [.option, .shift]]
    let modifiedKeyboardKeys: [RemappingKeyboardKey] =
      [.arrowUp, .arrowDown, .arrowLeft, .arrowRight] + [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
      ] + [.f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20]
    let modifiedKeyboard = modifiedKeyboardKeys.flatMap { key in
      modifierGroups.map { modifiers in
        RemappingDestination.keyboard(key: key, modifiers: modifiers)
      }
    }
    let keyboard = (plainKeyboard + modifiedKeyboard).map { destination in
      Self(destination: destination, title: RuntimePresentation.destinationLabel(destination))
    }
    let mouse = RemappingMouseButton.allCases.map { button in
      let destination = RemappingDestination.mouseButton(button)
      return Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination)
      )
    }
    let pointerAxes: [RemappingPointerAxis] = [.x, .y]
    let pointer = pointerAxes.flatMap { axis in
      [RemappingDestination.mouseMovement(axis), RemappingDestination.scroll(axis)]
    }.map { destination in
      Self(destination: destination, title: RuntimePresentation.destinationLabel(destination))
    }
    let gamepadDestinations =
      RemappingButton.allCases.filter(\.supportsVirtualOutput).map(
        RemappingDestination.gamepadButton
      ) + RemappingDpadDirection.allCases.map(RemappingDestination.gamepadDpad)
      + RemappingAxis.allCases.map(RemappingDestination.gamepadAxis)
    let gamepad = gamepadDestinations.map { destination in
      Self(destination: destination, title: RuntimePresentation.destinationLabel(destination))
    }
    return keyboard + mouse + pointer + gamepad + physical
  }()

  private static func isCompatible(
    _ destination: RemappingDestination,
    with source: RemappingSource
  ) -> Bool {
    if case .gamepadButton(let button) = destination, !button.supportsVirtualOutput { return false }
    switch source {
    case .axis: return destination.isContinuous
    case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
      .touchSwipe:
      return !destination.isContinuous
    }
  }
}

enum RuntimeProfileDraftError: Error, LocalizedError, Equatable, Sendable {
  case bindingNotFound(UUID)
  case chordNotFound(UUID)
  case layerNotFound(UUID)
  case sequenceNotFound(UUID)
  case validation(RemappingValidationError)

  var errorDescription: String? {
    switch self {
    case .bindingNotFound, .chordNotFound, .layerNotFound, .sequenceNotFound:
      return OJDLocalized.string(
        "error.selectedProfileItemMissing",
        fallback: "The selected profile item is no longer available."
      )
    case .validation:
      return OJDLocalized.string(
        "error.reviewAssignmentsBeforeSave",
        fallback: "Review the assignments before saving this profile."
      )
    }
  }
}

struct RuntimeProfileDraft: Sendable, Equatable {
  let profile: RemappingProfile

  func validatedProfile() throws -> RemappingProfile { try Self.validate(profile) }

  func settingAdditionalActions(
    _ actions: [RemappingAction],
    for bindingID: UUID,
    layerID: UUID? = nil
  ) throws -> Self {
    let transform: (RemappingBinding) -> RemappingBinding = { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: actions
      )
    }
    if let layerID {
      return try replacingLayerBinding(layerID: layerID, bindingID: bindingID, transform: transform)
    }
    return try replacingBinding(bindingID, transform)
  }

  func settingMetadata(
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope
  ) throws -> Self {
    try replacingProfile(name: name, device: device, applicationScope: applicationScope)
  }

  func settingOutputPolicy(_ outputPolicy: RemappingOutputPolicy) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingLayerMotionTuning(_ tuning: RemappingMotionTuning?, for layerID: UUID) throws -> Self
  {
    guard let index = profile.layers.firstIndex(where: { $0.id == layerID }) else {
      throw RuntimeProfileDraftError.layerNotFound(layerID)
    }
    var layers = profile.layers
    let layer = layers[index]
    layers[index] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: layer.bindings,
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: tuning
    )
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingStickMappings(_ mappings: [RemappingStickMapping]) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: mappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingTriggerMappings(_ mappings: [RemappingTriggerMapping]) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: mappings,
      touchMappings: profile.touchMappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingTouchMappings(_ mappings: [RemappingTouchMapping]) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: mappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingMotionTuning(
    _ tuning: RemappingMotionTuning,
    gyroOutput: RemappingGyroOutput? = nil
  ) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: tuning,
      gyroOutput: gyroOutput ?? profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: profile.bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func settingDestination(_ destination: RemappingDestination, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func settingSource(_ source: RemappingSource, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      let tuning: RemappingAxisTuning?
      switch source {
      case .axis, .axisDirection: tuning = binding.axisTuning ?? .default
      case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
        tuning = nil
      }
      let destination = Self.destination(for: source, preserving: binding.destination)
      return RemappingBinding(
        id: binding.id,
        source: source,
        destination: destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: tuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  private static func destination(
    for source: RemappingSource,
    preserving current: RemappingDestination
  ) -> RemappingDestination {
    let options = DestinationOption.options(for: source, including: current)
    if let preserved = options.first(where: { $0.destination == current }) {
      return preserved.destination
    }
    return options.first?.destination ?? current
  }

  func settingAxisTuning(_ axisTuning: RemappingAxisTuning?, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func settingBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    doubleTap: RemappingDoubleTap?,
    for bindingID: UUID
  ) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: behavior ?? binding.behavior,
        pulseDurationMs: (behavior ?? binding.behavior) == .pulse
          ? pulseDurationMs ?? binding.pulseDurationMs : RemappingBinding.defaultPulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: turbo,
        longHold: longHold,
        doubleTap: doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func addingBinding(
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil
  ) throws -> Self {
    let tuning: RemappingAxisTuning?
    switch source {
    case .axis, .axisDirection: tuning = axisTuning ?? .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe:
      tuning = nil
    }
    let binding = RemappingBinding(source: source, destination: destination, axisTuning: tuning)
    var bindings = profile.bindings
    bindings.append(binding)
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func removingBinding(_ bindingID: UUID) throws -> Self {
    guard profile.bindings.contains(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    let bindings = profile.bindings.filter { $0.id != bindingID }
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  func addingChord(
    sources: Set<RemappingSource>,
    destination: RemappingDestination,
    mode: RemappingChordMode = .modifier,
    windowMs: Double = 50
  ) throws -> Self {
    try replacingProfile(
      chords: profile.chords + [
        RemappingChord(sources: sources, destination: destination, mode: mode, windowMs: windowMs)
      ]
    )
  }

  func removingChord(_ chordID: UUID) throws -> Self {
    guard profile.chords.contains(where: { $0.id == chordID }) else {
      throw RuntimeProfileDraftError.chordNotFound(chordID)
    }
    return try replacingProfile(chords: profile.chords.filter { $0.id != chordID })
  }

  func addingSequence(
    sources: [RemappingSource],
    windowMs: Double,
    destination: RemappingDestination
  ) throws -> Self {
    try replacingProfile(
      sequences: profile.sequences + [
        RemappingSequence(sources: sources, windowMs: windowMs, destination: destination)
      ]
    )
  }

  func removingSequence(_ sequenceID: UUID) throws -> Self {
    guard profile.sequences.contains(where: { $0.id == sequenceID }) else {
      throw RuntimeProfileDraftError.sequenceNotFound(sequenceID)
    }
    return try replacingProfile(sequences: profile.sequences.filter { $0.id != sequenceID })
  }

  func addingLayer(
    name: String,
    activator: RemappingSource,
    activationMode: RemappingLayerActivation
  ) throws -> Self {
    try replacingProfile(
      layers: profile.layers + [
        RemappingLayer(name: name, activationMode: activationMode, activator: activator)
      ]
    )
  }

  func removingLayer(_ layerID: UUID) throws -> Self {
    guard profile.layers.contains(where: { $0.id == layerID }) else {
      throw RuntimeProfileDraftError.layerNotFound(layerID)
    }
    return try replacingProfile(layers: profile.layers.filter { $0.id != layerID })
  }

  func settingLayerBinding(
    layerID: UUID,
    source: RemappingSource,
    destination: RemappingDestination,
    axisTuning: RemappingAxisTuning? = nil,
    turbo: RemappingTurbo? = nil,
    longHold: RemappingLongHold? = nil,
    doubleTap: RemappingDoubleTap? = nil
  ) throws -> Self {
    guard let index = profile.layers.firstIndex(where: { $0.id == layerID }) else {
      throw RuntimeProfileDraftError.layerNotFound(layerID)
    }
    var layers = profile.layers
    let layer = layers[index]
    let existingID = layer.bindings.first { $0.source == source }?.id
    let binding = RemappingBinding(
      id: existingID ?? UUID(),
      source: source,
      destination: destination,
      behavior: layer.bindings.first { $0.source == source }?.behavior ?? .hold,
      pulseDurationMs: layer.bindings.first { $0.source == source }?.pulseDurationMs
        ?? RemappingBinding.defaultPulseDurationMs,
      axisTuning: axisTuning ?? Self.defaultTuning(for: source),
      turbo: turbo,
      longHold: longHold,
      doubleTap: doubleTap,
      additionalActions: layer.bindings.first { $0.source == source }?.additionalActions ?? []
    )
    layers[index] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: layer.bindings.filter { $0.source != source } + [binding],
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: layer.motionTuning
    )
    return try replacingProfile(layers: layers)
  }

  func settingLayerBindingAxisTuning(
    layerID: UUID,
    bindingID: UUID,
    axisTuning: RemappingAxisTuning
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: binding.behavior,
        pulseDurationMs: binding.pulseDurationMs,
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func settingLayerBindingBehaviors(
    behavior: RemappingBindingBehavior? = nil,
    pulseDurationMs: Double? = nil,
    layerID: UUID,
    bindingID: UUID,
    turbo: RemappingTurbo?,
    longHold: RemappingLongHold?,
    doubleTap: RemappingDoubleTap?
  ) throws -> Self {
    try replacingLayerBinding(layerID: layerID, bindingID: bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: binding.destination,
        behavior: behavior ?? binding.behavior,
        pulseDurationMs: (behavior ?? binding.behavior) == .pulse
          ? pulseDurationMs ?? binding.pulseDurationMs : RemappingBinding.defaultPulseDurationMs,
        axisTuning: binding.axisTuning,
        turbo: turbo,
        longHold: longHold,
        doubleTap: doubleTap,
        additionalActions: binding.additionalActions
      )
    }
  }

  func removingLayerBinding(layerID: UUID, bindingID: UUID) throws -> Self {
    guard let index = profile.layers.firstIndex(where: { $0.id == layerID }) else {
      throw RuntimeProfileDraftError.layerNotFound(layerID)
    }
    var layers = profile.layers
    let layer = layers[index]
    guard layer.bindings.contains(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    layers[index] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: layer.bindings.filter { $0.id != bindingID },
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: layer.motionTuning
    )
    return try replacingProfile(layers: layers)
  }

  private func replacingLayerBinding(
    layerID: UUID,
    bindingID: UUID,
    transform: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    guard let layerIndex = profile.layers.firstIndex(where: { $0.id == layerID }) else {
      throw RuntimeProfileDraftError.layerNotFound(layerID)
    }
    var layers = profile.layers
    let layer = layers[layerIndex]
    guard let bindingIndex = layer.bindings.firstIndex(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    var bindings = layer.bindings
    bindings[bindingIndex] = transform(bindings[bindingIndex])
    layers[layerIndex] = RemappingLayer(
      id: layer.id,
      name: layer.name,
      activationMode: layer.activationMode,
      activator: layer.activator,
      bindings: bindings,
      chords: layer.chords,
      sequences: layer.sequences,
      motionTuning: layer.motionTuning
    )
    return try replacingProfile(layers: layers)
  }

  private func replacingBinding(
    _ bindingID: UUID,
    _ makeBinding: (RemappingBinding) -> RemappingBinding
  ) throws -> Self {
    guard let index = profile.bindings.firstIndex(where: { $0.id == bindingID }) else {
      throw RuntimeProfileDraftError.bindingNotFound(bindingID)
    }
    var bindings = profile.bindings
    bindings[index] = makeBinding(bindings[index])
    let candidate = RemappingProfile(
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  private func replacingProfile(
    name: String? = nil,
    device: RemappingDeviceScope? = nil,
    applicationScope: RemappingApplicationScope? = nil,
    bindings: [RemappingBinding]? = nil,
    chords: [RemappingChord]? = nil,
    sequences: [RemappingSequence]? = nil,
    layers: [RemappingLayer]? = nil
  ) throws -> Self {
    let candidate = RemappingProfile(
      id: profile.id,
      name: name ?? profile.name,
      device: device ?? profile.device,
      applicationScope: applicationScope ?? profile.applicationScope,
      outputPolicy: profile.outputPolicy,
      motionTuning: profile.motionTuning,
      gyroOutput: profile.gyroOutput,
      joyConPair: profile.joyConPair,
      stickMappings: profile.stickMappings,
      triggerMappings: profile.triggerMappings,
      touchMappings: profile.touchMappings,
      bindings: bindings ?? profile.bindings,
      chords: chords ?? profile.chords,
      sequences: sequences ?? profile.sequences,
      layers: layers ?? profile.layers
    )
    return Self(profile: try Self.validate(candidate))
  }

  private static func defaultTuning(for source: RemappingSource) -> RemappingAxisTuning? {
    switch source {
    case .axis, .axisDirection: .default
    case .button, .dpad, .triggerStage, .motionLean, .touchContact, .touchGrid, .touchSwipe: nil
    }
  }

  private static func validate(_ profile: RemappingProfile) throws -> RemappingProfile {
    do {
      try profile.validate()
      return profile
    } catch let error as RemappingValidationError {
      throw RuntimeProfileDraftError.validation(error)
    } catch { throw RuntimeProfileDraftError.validation(.encodingFailed) }
  }
}
