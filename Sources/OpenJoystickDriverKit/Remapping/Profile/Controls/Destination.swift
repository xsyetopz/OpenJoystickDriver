import Foundation

/// The output a binding drives: virtual gamepad, keyboard, pointer, or physical controller.
public enum RemappingDestination: Codable, Equatable, Hashable, Sendable {
  /// A button of the virtual gamepad.
  case gamepadButton(Control)
  /// A d-pad direction of the virtual gamepad.
  case gamepadDpad(RemappingDpadDirection)
  /// An axis of the virtual gamepad.
  case gamepadAxis(RemappingAxis)
  /// A keyboard key with its modifiers.
  case keyboard(key: RemappingKeyboardKey, modifiers: Set<RemappingKeyModifier>)
  /// A pointer button.
  case mouseButton(RemappingMouseButton)
  /// Pointer movement along one axis.
  case mouseMovement(RemappingPointerAxis)
  /// The cursor's position along one axis: -1 to 1 maps across the main display.
  case pointerPosition(RemappingPointerAxis)
  /// Scrolling along one axis.
  case scroll(RemappingPointerAxis)
  /// A channel of the physical controller, such as rumble or light.
  case physical(RemappingPhysicalOutput)
  /// The macro of the profile with this identifier.
  case macro(UUID)
  /// Activates a profile of the same controller model, as `ojd profile activate` does.
  case profileSwitch(RemappingProfileTarget)
  /// Sets a layer of the same profile on, off or flips it.
  case layerSet(layer: UUID, mode: RemappingSwitchMode)
  /// Sets the controller's pause on, off or flips it.
  case pause(RemappingSwitchMode)
  /// Sends one system-defined key such as volume up; it follows the source, down then up.
  case systemKey(RemappingSystemKey)
  /// Runs a system action that has no parameter.
  case systemAction(RemappingSystemActionKind)
  /// Opens the application with this bundle identifier.
  case openApplication(bundleIdentifier: String)
  /// Opens this absolute URL.
  case openURL(String)
  /// Runs the Shortcut with this name.
  case runShortcut(String)
  /// Types this text.
  case typeText(String)
  /// Says `text` aloud, with the voice `voice` names or the system voice.
  case speak(text: String, voice: String?)
  /// A MIDI note: note-on on press, note-off on release. Channel 1 to 16, note 0 to 127, velocity
  /// 1 to 127.
  case midiNote(channel: Int, note: Int, velocity: Int)
  /// A MIDI controller: 127 and 0 for a button, the position scaled to 0 to 127 for an axis.
  case midiControlChange(channel: Int, controller: Int)

  /// Whether the destination can repeat as turbo: a keyboard key, pointer button or virtual gamepad
  /// button or d-pad direction.
  public var acceptsTurbo: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad: true
    case .mouseMovement, .pointerPosition, .scroll, .gamepadAxis, .physical, .macro, .profileSwitch,
      .layerSet, .pause, .systemKey, .systemAction, .openApplication, .openURL, .runShortcut, .typeText,
      .speak,
      .midiNote, .midiControlChange:
      false
    }
  }

  /// Whether the destination takes a continuous amount: pointer movement, scrolling or a virtual
  /// gamepad axis.
  public var isContinuous: Bool {
    switch self {
    case .keyboard, .mouseButton, .gamepadButton, .gamepadDpad, .physical, .macro, .profileSwitch,
      .layerSet, .pause, .systemKey, .systemAction, .openApplication, .openURL, .runShortcut,
      .typeText, .speak,
      .midiNote, .midiControlChange:
      false
    case .mouseMovement, .pointerPosition, .scroll, .gamepadAxis: true
    }
  }

  /// Value of the `type` field that selects the case in a profile document.
  private enum Kind: String, Codable {
    /// The `Keyboard` case.
    case keyboard = "Keyboard"
    /// The `GamepadButton` case.
    case gamepadButton = "GamepadButton"
    /// The `GamepadDpad` case.
    case gamepadDpad = "GamepadDpad"
    /// The `GamepadAxis` case.
    case gamepadAxis = "GamepadAxis"
    /// The `MouseButton` case.
    case mouseButton = "MouseButton"
    /// The `MouseMovement` case.
    case mouseMovement = "MouseMovement"
    /// The `PointerPosition` case.
    case pointerPosition = "PointerPosition"
    /// The `Scroll` case.
    case scroll = "Scroll"
    /// The `Physical` case.
    case physical = "Physical"
    /// The `Macro` case.
    case macro = "Macro"
    /// The `ProfileSwitch` case.
    case profileSwitch = "ProfileSwitch"
    /// The `LayerSet` case.
    case layerSet = "LayerSet"
    /// The `Pause` case.
    case pause = "Pause"
    /// The `SystemKey` case.
    case systemKey = "SystemKey"
    /// The `SystemAction` case.
    case systemAction = "SystemAction"
    /// The `OpenApplication` case.
    case openApplication = "OpenApplication"
    /// The `OpenURL` case.
    case openURL = "OpenURL"
    /// The `RunShortcut` case.
    case runShortcut = "RunShortcut"
    /// The `TypeText` case.
    case typeText = "TypeText"
    /// The `Speak` case.
    case speak = "Speak"
    /// The `MidiNote` case.
    case midiNote = "MidiNote"
    /// The `MidiControlChange` case.
    case midiControlChange = "MidiControlChange"

    /// Keys that a profile document may give for this case, which `type` selects.
    var fields: [CodingKeys] {
      switch self {
      case .keyboard: [.type, .key, .modifiers]
      case .gamepadButton, .mouseButton: [.type, .button]
      case .gamepadDpad: [.type, .direction]
      case .gamepadAxis, .mouseMovement, .pointerPosition, .scroll: [.type, .axis]
      case .physical: [.type, .physical]
      case .macro: [.type, .macro]
      case .profileSwitch: [.type, .profile]
      case .layerSet: [.type, .layer, .mode]
      case .pause: [.type, .mode]
      case .systemKey: [.type, .systemKey]
      case .systemAction: [.type, .action]
      case .openApplication: [.type, .bundleIdentifier]
      case .openURL: [.type, .url]
      case .runShortcut: [.type, .name]
      case .typeText: [.type, .text]
      case .speak: [.type, .text, .voice]
      case .midiNote: [.type, .channel, .note, .velocity]
      case .midiControlChange: [.type, .channel, .controller]
      }
    }
  }

  /// Profile document keys of a destination, merged across all cases.
  private enum CodingKeys: String, CodingKey, CaseIterable {
    /// The JSON key of `type`.
    case type
    /// The JSON key of `key`.
    case key
    /// The JSON key of `modifiers`.
    case modifiers
    /// The JSON key of `button`.
    case button
    /// The JSON key of `axis`.
    case axis
    /// The JSON key of `direction`.
    case direction
    /// The JSON key of `physical`.
    case physical
    /// The JSON key of `macro`.
    case macro
    /// The JSON key of `profile`.
    case profile
    /// The JSON key of `layer`.
    case layer
    /// The JSON key of `mode`.
    case mode
    /// The JSON key of `systemKey`.
    case systemKey
    /// The JSON key of `action`.
    case action
    /// The JSON key of `bundleIdentifier`.
    case bundleIdentifier
    /// The JSON key of `url`.
    case url
    /// The JSON key of `name`.
    case name
    /// The JSON key of `text`.
    case text
    /// The JSON key of `voice`.
    case voice
    /// The JSON key of `channel`.
    case channel
    /// The JSON key of `note`.
    case note
    /// The JSON key of `velocity`.
    case velocity
    /// The JSON key of `controller`.
    case controller
  }

  /// Decodes a destination from a profile document.
  ///
  /// The `type` field selects the case, and keys that belong to another case are rejected.
  /// - Throws: `DecodingError` for an unknown or misplaced key, a missing key or a bad value.
  public init(from decoder: any Decoder) throws {
    try decoder.rejectUnknownKeys(CodingKeys.self)
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try container.decode(Kind.self, forKey: .type)
    try container.rejectKeys(otherThan: kind.fields)
    switch kind {
    case .gamepadAxis: self = .gamepadAxis(try container.decode(RemappingAxis.self, forKey: .axis))
    case .gamepadDpad:
      self = .gamepadDpad(try container.decode(RemappingDpadDirection.self, forKey: .direction))
    case .gamepadButton:
      self = .gamepadButton(try container.decode(Control.self, forKey: .button))
    case .keyboard:
      let modifiers = try container.decode([RemappingKeyModifier].self, forKey: .modifiers)
      self = .keyboard(
        key: try container.decode(RemappingKeyboardKey.self, forKey: .key),
        modifiers: Set(modifiers)
      )
    case .mouseButton:
      self = .mouseButton(try container.decode(RemappingMouseButton.self, forKey: .button))
    case .mouseMovement:
      self = .mouseMovement(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .pointerPosition:
      self = .pointerPosition(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .scroll: self = .scroll(try container.decode(RemappingPointerAxis.self, forKey: .axis))
    case .physical:
      self = .physical(try container.decode(RemappingPhysicalOutput.self, forKey: .physical))
    case .macro: self = .macro(try container.decode(UUID.self, forKey: .macro))
    case .profileSwitch:
      self = .profileSwitch(try container.decode(RemappingProfileTarget.self, forKey: .profile))
    case .layerSet:
      self = .layerSet(
        layer: try container.decode(UUID.self, forKey: .layer),
        mode: try container.decode(RemappingSwitchMode.self, forKey: .mode)
      )
    case .pause: self = .pause(try container.decode(RemappingSwitchMode.self, forKey: .mode))
    case .systemKey:
      self = .systemKey(try container.decode(RemappingSystemKey.self, forKey: .systemKey))
    case .systemAction:
      self = .systemAction(try container.decode(RemappingSystemActionKind.self, forKey: .action))
    case .openApplication:
      self = .openApplication(
        bundleIdentifier: try container.decode(String.self, forKey: .bundleIdentifier)
      )
    case .openURL: self = .openURL(try container.decode(String.self, forKey: .url))
    case .runShortcut: self = .runShortcut(try container.decode(String.self, forKey: .name))
    case .typeText: self = .typeText(try container.decode(String.self, forKey: .text))
    case .speak:
      self = .speak(
        text: try container.decode(String.self, forKey: .text),
        voice: try container.decodeIfPresent(String.self, forKey: .voice)
      )
    case .midiNote:
      self = .midiNote(
        channel: try container.decode(Int.self, forKey: .channel),
        note: try container.decode(Int.self, forKey: .note),
        velocity: try container.decode(Int.self, forKey: .velocity)
      )
    case .midiControlChange:
      self = .midiControlChange(
        channel: try container.decode(Int.self, forKey: .channel),
        controller: try container.decode(Int.self, forKey: .controller)
      )
    }
    guard midiFieldsAreInRange else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription:
            "MIDI channel is 1 to 16, note and controller 0 to 127, velocity 1 to 127"
        )
      )
    }
  }

  /// Encodes the case under its `type` value with only its own keys; keyboard modifiers are sorted.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .gamepadAxis(let axis):
      try container.encode(Kind.gamepadAxis, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .gamepadDpad(let direction):
      try container.encode(Kind.gamepadDpad, forKey: .type)
      try container.encode(direction, forKey: .direction)
    case .gamepadButton(let button):
      try container.encode(Kind.gamepadButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .keyboard(let key, let modifiers):
      try container.encode(Kind.keyboard, forKey: .type)
      try container.encode(key, forKey: .key)
      try container.encode(modifiers.sorted { $0.rawValue < $1.rawValue }, forKey: .modifiers)
    case .mouseButton(let button):
      try container.encode(Kind.mouseButton, forKey: .type)
      try container.encode(button, forKey: .button)
    case .mouseMovement(let axis):
      try container.encode(Kind.mouseMovement, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .pointerPosition(let axis):
      try container.encode(Kind.pointerPosition, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .scroll(let axis):
      try container.encode(Kind.scroll, forKey: .type)
      try container.encode(axis, forKey: .axis)
    case .physical(let output):
      try container.encode(Kind.physical, forKey: .type)
      try container.encode(output, forKey: .physical)
    case .macro(let id):
      try container.encode(Kind.macro, forKey: .type)
      try container.encode(id, forKey: .macro)
    case .profileSwitch(let target):
      try container.encode(Kind.profileSwitch, forKey: .type)
      try container.encode(target, forKey: .profile)
    case .layerSet(let layer, let mode):
      try container.encode(Kind.layerSet, forKey: .type)
      try container.encode(layer, forKey: .layer)
      try container.encode(mode, forKey: .mode)
    case .pause(let mode):
      try container.encode(Kind.pause, forKey: .type)
      try container.encode(mode, forKey: .mode)
    case .systemKey(let key):
      try container.encode(Kind.systemKey, forKey: .type)
      try container.encode(key, forKey: .systemKey)
    case .systemAction(let action):
      try container.encode(Kind.systemAction, forKey: .type)
      try container.encode(action, forKey: .action)
    case .openApplication(let bundleIdentifier):
      try container.encode(Kind.openApplication, forKey: .type)
      try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
    case .openURL(let url):
      try container.encode(Kind.openURL, forKey: .type)
      try container.encode(url, forKey: .url)
    case .runShortcut(let name):
      try container.encode(Kind.runShortcut, forKey: .type)
      try container.encode(name, forKey: .name)
    case .typeText(let text):
      try container.encode(Kind.typeText, forKey: .type)
      try container.encode(text, forKey: .text)
    case .speak(let text, let voice):
      try container.encode(Kind.speak, forKey: .type)
      try container.encode(text, forKey: .text)
      try container.encodeIfPresent(voice, forKey: .voice)
    case .midiNote(let channel, let note, let velocity):
      try container.encode(Kind.midiNote, forKey: .type)
      try container.encode(channel, forKey: .channel)
      try container.encode(note, forKey: .note)
      try container.encode(velocity, forKey: .velocity)
    case .midiControlChange(let channel, let controller):
      try container.encode(Kind.midiControlChange, forKey: .type)
      try container.encode(channel, forKey: .channel)
      try container.encode(controller, forKey: .controller)
    }
  }
}
