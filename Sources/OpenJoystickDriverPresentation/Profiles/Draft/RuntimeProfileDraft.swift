import Foundation
import OpenJoystickDriverKit

/// A destination the destination pickers list, with its title and whether the controller
/// supports it.
struct DestinationOption: Hashable {
  /// The destination.
  let destination: RemappingDestination
  /// The title in the picker.
  let title: String
  /// Whether the controller supports the destination.
  let isSupported: Bool

  /// Returns the destinations that fit `source` and that the controller supports, and `current`
  /// when it fits the source and is not among them.
  ///
  /// - Parameters:
  ///   - source: The source the destinations must fit.
  ///   - current: The destination to keep in the list.
  ///   - capabilities: What the controller has; nil means every destination is supported.
  ///   - macros: The macros of the profile, offered as destinations of a discrete source.
  ///   - layers: The layers of the profile; when given, the profile control destinations of a
  ///     discrete source are offered with them.
  /// - Returns: The destinations that fit `source` and that the controller supports, and `current`
  ///   when it fits the source and is not among them.
  static func options(
    for source: RemappingSource,
    including current: RemappingDestination? = nil,
    capabilities: ControllerProfileCapabilities? = nil,
    macros: [RemappingMacro] = [],
    layers: [RemappingLayer]? = nil
  ) -> [Self] {
    var options = all.filter {
      isCompatible($0.destination, with: source)
        && ProfileCapabilityPolicy.supports($0.destination, capabilities: capabilities)
    }
    options += macros.filter { isCompatible(.macro($0.id), with: source) }.map {
      Self(destination: .macro($0.id), title: $0.name, isSupported: true)
    }
    if let layers {
      let control = profileControl(layers: layers)
      options += control.filter { isCompatible($0.destination, with: source) }
    }
    if let current, isCompatible(current, with: source),
      !options.contains(where: { $0.destination == current })
    {
      options.append(
        Self(
          destination: current,
          title: RuntimePresentation.destinationLabel(current),
          isSupported: ProfileCapabilityPolicy.supports(current, capabilities: capabilities)
        )
      )
    }
    return options
  }

  /// The profile control destinations: the next and previous profile, a pause and a switch of each
  /// layer, each in the three modes.
  private static func profileControl(layers: [RemappingLayer]) -> [Self] {
    let modes = RemappingSwitchMode.allCases
    let destinations: [RemappingDestination] =
      [.profileSwitch(.next), .profileSwitch(.previous)] + modes.map { .pause($0) }
      + layers.flatMap { layer in modes.map { .layerSet(layer: layer.id, mode: $0) } }
    return destinations.map {
      Self(
        destination: $0,
        title: RuntimePresentation.destinationLabel($0, layers: layers),
        isSupported: true
      )
    }
  }

  /// Every destination the pickers know.
  ///
  /// These are keyboard keys, with modifier groups for the arrow and function keys, mouse buttons,
  /// pointer movement and scroll, system keys and actions, gamepad outputs and physical outputs.
  /// Open application, open URL, run Shortcut and type text carry a value, so a picker cannot list
  /// them; the CLI and profile files set them.
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
      [[.meta], [.control], [.alt], [.shift]] + [
        [.meta, .control], [.meta, .alt], [.meta, .shift],
      ] + [[.control, .alt], [.control, .shift], [.alt, .shift]]
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
      Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination),
        isSupported: true
      )
    }
    let mouse = RemappingMouseButton.allCases.map { button in
      let destination = RemappingDestination.mouseButton(button)
      return Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination),
        isSupported: true
      )
    }
    let pointerAxes: [RemappingPointerAxis] = [.x, .y]
    let pointer = pointerAxes.flatMap { axis in
      [RemappingDestination.mouseMovement(axis), RemappingDestination.scroll(axis)]
    }.map { destination in
      Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination),
        isSupported: true
      )
    }
    let gamepadDestinations =
      Control.allCases.filter(\.supportsVirtualOutput).map(
        RemappingDestination.gamepadButton
      ) + RemappingDpadDirection.allCases.map(RemappingDestination.gamepadDpad)
      + RemappingAxis.allCases.map(RemappingDestination.gamepadAxis)
    let gamepad = gamepadDestinations.map { destination in
      Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination),
        isSupported: true
      )
    }
    let speak = RemappingDestination.speak(
      text: OJDLocalized.string("ui.profiles.speak.defaultText"),
      voice: nil
    )
    let systemDestinations =
      RemappingSystemKey.allCases.map(RemappingDestination.systemKey)
      + RemappingSystemActionKind.allCases.map(RemappingDestination.systemAction)
    let system = (systemDestinations + [speak]).map { destination in
      Self(
        destination: destination,
        title: RuntimePresentation.destinationLabel(destination),
        isSupported: true
      )
    }
    return keyboard + mouse + pointer + system + gamepad + physical
  }()

  /// Returns whether `destination` fits `source`: an axis takes a continuous destination, any
  /// other source a discrete one, and a gamepad button needs virtual output.
  private static func isCompatible(
    _ destination: RemappingDestination,
    with source: RemappingSource
  ) -> Bool {
    if case .gamepadButton(let button) = destination, !button.supportsVirtualOutput { return false }
    switch source {
    case .axis: return destination.isContinuous
    case .axisDirection, .triggerStage, .motionLean, .button, .dpad, .touchContact, .touchGrid,
      .touchSwipe, .stickRegion, .triggerBand, .touchArea:
      return !destination.isContinuous
    }
  }
}

/// Why an edit of the profile draft failed.
enum RuntimeProfileDraftError: Error, LocalizedError, Equatable, Sendable {
  /// No assignment has the identifier.
  case bindingNotFound(UUID)
  /// No chord has the identifier.
  case chordNotFound(UUID)
  /// No layer has the identifier.
  case layerNotFound(UUID)
  /// No sequence has the identifier.
  case sequenceNotFound(UUID)
  /// The result breaks a profile rule.
  case validation(RemappingValidationError)

  /// The message of the failure: the missing item, or the result that breaks a profile rule.
  var errorDescription: String? {
    switch self {
    case .bindingNotFound, .chordNotFound, .layerNotFound, .sequenceNotFound:
      return OJDLocalized.string(
        "ui.error.selectedProfileItemMissing"
      )
    case .validation:
      return OJDLocalized.string(
        "ui.error.reviewAssignmentsBeforeSave"
      )
    }
  }
}

/// A profile the editor changes; every edit returns a validated copy.
struct RuntimeProfileDraft: Sendable, Equatable {
  /// The profile.
  let profile: RemappingProfile

  /// Returns the profile after validating it.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when it breaks a profile rule.
  func validatedProfile() throws -> RemappingProfile { try Self.validate(profile) }

  /// Returns the draft with the additional actions of an assignment set, in the layer when
  /// `layerID` is given.
  ///
  /// - Throws: ``RuntimeProfileDraftError`` when the layer or assignment is missing or the result
  ///   breaks a profile rule.
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
        multiTap: binding.multiTap,
        additionalActions: actions
      )
    }
    if let layerID {
      return try replacingLayerBinding(layerID: layerID, bindingID: bindingID, transform: transform)
    }
    return try replacingBinding(bindingID, transform)
  }

  /// Returns the draft with the profile's name, device scope and application scope set.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when they break a profile rule.
  func settingMetadata(
    name: String,
    device: RemappingDeviceScope,
    applicationScope: RemappingApplicationScope
  ) throws -> Self {
    Self(
      profile: try Self.validate(
        profile.replacing(name: name, device: device, applicationScope: applicationScope)
      )
    )
  }

  /// Returns the draft with the output policy set.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when it breaks a profile rule.
  func settingOutputPolicy(_ outputPolicy: RemappingOutputPolicy) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(outputPolicy: outputPolicy)))
  }

  /// Returns the draft with the physical color set; nil clears it.
  ///
  /// - Throws: ``RuntimeProfileDraftError/validation(_:)`` when it breaks a profile rule.
  func settingPhysicalColor(_ physicalColor: ControllerColor?) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(physicalColor: .some(physicalColor))))
  }

  /// Returns the draft with the name set.
  func settingName(_ name: String) -> Self { Self(profile: profile.replacing(name: name)) }

}
