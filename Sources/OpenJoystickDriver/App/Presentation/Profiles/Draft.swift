import Foundation
import OpenJoystickDriverKit

struct SourceOption: Hashable {
  let source: RemappingSource
  let title: String

  static func options(including current: RemappingSource? = nil) -> [Self] {
    var options = all
    if let current, !options.contains(where: { $0.source == current }) {
      options.append(Self(source: current, title: RuntimePresentation.sourceLabel(current)))
    }
    return options
  }

  static let all: [Self] = {
    let buttons: [RemappingSource] = RemappingButton.allCases.compactMap { button in
      // The Guide/Home control remains reserved for the operating system in the ordinary UI.
      guard button != .guide else { return nil }
      return .button(button)
    }
    let dpad: [RemappingSource] = RemappingDpadDirection.allCases.map { .dpad($0) }
    let axes: [RemappingSource] = RemappingAxis.allCases.flatMap { axis in
      [.axis(axis), .axisDirection(axis, .negative), .axisDirection(axis, .positive)]
    }
    return (buttons + dpad + axes).map {
      .init(source: $0, title: RuntimePresentation.sourceLabel($0))
    }
  }()
}

struct DestinationOption: Hashable {
  let destination: RemappingDestination
  let title: String

  static func options(for source: RemappingSource, including current: RemappingDestination? = nil)
    -> [Self]
  {
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
        [.command, .control], [.command, .option], [.command, .shift]
      ] + [[.control, .option], [.control, .shift], [.option, .shift]]
    let modifiedKeyboardKeys: [RemappingKeyboardKey] =
      [.arrowUp, .arrowDown, .arrowLeft, .arrowRight] + [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10
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
    return keyboard + mouse + pointer
  }()

  private static func isCompatible(
    _ destination: RemappingDestination,
    with source: RemappingSource
  ) -> Bool {
    switch source {
    case .axis: return destination.isContinuous
    case .axisDirection, .button, .dpad: return !destination.isContinuous
    }
  }
}

enum RuntimeProfileDraftError: Error, LocalizedError, Equatable, Sendable {
  case bindingNotFound(UUID)
  case validation(RemappingValidationError)

  var errorDescription: String? {
    switch self {
    case .bindingNotFound: return "The selected assignment is no longer available."
    case .validation: return "Review the assignments before saving this profile."
    }
  }
}

struct RuntimeProfileDraft: Sendable, Equatable {
  let profile: RemappingProfile

  func validatedProfile() throws -> RemappingProfile { try Self.validate(profile) }

  func settingDestination(_ destination: RemappingDestination, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      RemappingBinding(
        id: binding.id,
        source: binding.source,
        destination: destination,
        axisTuning: binding.axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
      )
    }
  }

  func settingSource(_ source: RemappingSource, for bindingID: UUID) throws -> Self {
    try replacingBinding(bindingID) { binding in
      let tuning: RemappingAxisTuning?
      switch source {
      case .axis, .axisDirection: tuning = binding.axisTuning ?? .default
      case .button, .dpad: tuning = nil
      }
      let destination = Self.destination(for: source, preserving: binding.destination)
      return RemappingBinding(
        id: binding.id,
        source: source,
        destination: destination,
        axisTuning: tuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
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
        axisTuning: axisTuning,
        turbo: binding.turbo,
        longHold: binding.longHold,
        doubleTap: binding.doubleTap
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
    case .button, .dpad: tuning = nil
    }
    let binding = RemappingBinding(source: source, destination: destination, axisTuning: tuning)
    var bindings = profile.bindings
    bindings.append(binding)
    let candidate = RemappingProfile(
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
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
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
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
      schemaVersion: profile.schemaVersion,
      id: profile.id,
      name: profile.name,
      device: profile.device,
      applicationScope: profile.applicationScope,
      bindings: bindings,
      chords: profile.chords,
      sequences: profile.sequences,
      layers: profile.layers
    )
    return Self(profile: try Self.validate(candidate))
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
