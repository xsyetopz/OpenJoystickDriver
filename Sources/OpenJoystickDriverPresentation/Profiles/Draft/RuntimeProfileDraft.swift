import Foundation
import OpenJoystickDriverKit

struct DestinationOption: Hashable {
  let destination: RemappingDestination
  let title: String
  let isSupported: Bool

  static func options(
    for source: RemappingSource,
    including current: RemappingDestination? = nil,
    capabilities: ControllerProfileCapabilities? = nil
  ) -> [Self] {
    var options = all.filter {
      isCompatible($0.destination, with: source)
        && ProfileCapabilityPolicy.supports($0.destination, capabilities: capabilities)
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
      RemappingButton.allCases.filter(\.supportsVirtualOutput).map(
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
        "error.selectedProfileItemMissing"
      )
    case .validation:
      return OJDLocalized.string(
        "error.reviewAssignmentsBeforeSave"
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
    Self(
      profile: try Self.validate(
        profile.replacing(name: name, device: device, applicationScope: applicationScope)
      )
    )
  }

  func settingOutputPolicy(_ outputPolicy: RemappingOutputPolicy) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(outputPolicy: outputPolicy)))
  }

  func settingPhysicalColor(_ physicalColor: ControllerColor?) throws -> Self {
    Self(profile: try Self.validate(profile.replacing(physicalColor: .some(physicalColor))))
  }

  func settingName(_ name: String) -> Self { Self(profile: profile.replacing(name: name)) }

}
