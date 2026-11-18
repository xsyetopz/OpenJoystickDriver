@testable package import OpenJoystickDriverKit

extension ProtocolBindingResult {
  /// A `HIDDescriptor` binding with no observed interfaces, for descriptions whose binding
  /// decision a test does not examine.
  package static let hidDescriptorFixture = ProtocolBindingResult(
    binding: hidDescriptorBinding(),
    interfaces: []
  )

  /// A `HIDDescriptor` binding whose SDL_GameControllerDB line was rejected for `reason`, so the
  /// pad keeps the standard map.
  package static func sdlRejectedFixture(_ reason: String) -> ProtocolBindingResult {
    var binding = hidDescriptorBinding()
    binding.sdl = SDLBindingResolution(
      inputMapping: InputMapping(
        source: .standardHIDUsageMap,
        guid: nil,
        match: nil,
        unmapped: [],
        rejection: reason
      ),
      usageMap: nil
    )
    return ProtocolBindingResult(binding: binding, interfaces: [])
  }

  private static func hidDescriptorBinding() -> ProtocolBinding {
    ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: .hid,
      interfaceNumber: nil,
      rule: .hidDescriptor,
      matchedPredicates: [.hidDescriptorContract],
      record: nil
    )
  }
}
