import Foundation

/// One MIDI channel message that a `MidiNote` or `MidiControlChange` destination sends.
///
/// Channels are 1 to 16, as a profile writes them.
public enum RemappingMIDIMessage: Equatable, Sendable {
  /// Starts a note.
  case noteOn(channel: Int, note: Int, velocity: Int)
  /// Ends a note.
  case noteOff(channel: Int, note: Int)
  /// Sets a controller to a value from 0 to 127.
  case controlChange(channel: Int, controller: Int, value: Int)

  /// The bytes of the message on the wire.
  public var bytes: [UInt8] {
    switch self {
    case .noteOn(let channel, let note, let velocity):
      [UInt8(0x90 | (channel - 1)), UInt8(note), UInt8(velocity)]
    case .noteOff(let channel, let note): [UInt8(0x80 | (channel - 1)), UInt8(note), 0]
    case .controlChange(let channel, let controller, let value):
      [UInt8(0xB0 | (channel - 1)), UInt8(controller), UInt8(value)]
    }
  }
}

/// A MIDI source that could not be created.
public enum RemappingMIDIError: Error, Equatable, LocalizedError, Sendable {
  /// CoreMIDI refused to create the source with this status.
  case sourceRefused(status: Int32)

  /// The catalog code of the failure.
  public var errorCode: ErrorCode { .midiSourceRefused }

  /// The explanation of the code with the CoreMIDI status.
  public var errorDescription: String? {
    switch self {
    case .sourceRefused(let status): "\(errorCode.localizedExplanation) (\(status))"
    }
  }
}

/// Publishes the virtual MIDI source and sends messages through it; the macOS platform implements
/// it.
///
/// The engine opens the source before the first message of a profile that uses MIDI and closes it
/// after the last note-off of the last such profile.
public protocol RemappingMIDIOutput: AnyObject, Sendable {
  /// Publishes the source named `OpenJoystickDriver`.
  /// - Throws: ``RemappingMIDIError`` when the system refuses.
  func open() throws
  /// Sends a message through the open source.
  func send(_ message: RemappingMIDIMessage) throws
  /// Removes the source.
  func close()
}

extension RemappingDestination {
  /// Highest value of a note, a controller or a controller value.
  static let midiMaxData = 127

  /// Whether the destination is a `MidiNote` or `MidiControlChange`.
  var isMIDI: Bool {
    switch self {
    case .midiNote, .midiControlChange: true
    default: false
    }
  }

  /// Whether the destination is a `MidiControlChange`.
  public var isMIDIControlChange: Bool {
    if case .midiControlChange = self { return true }
    return false
  }

  /// Whether the channel, note, velocity and controller of a MIDI destination are in range.
  var midiFieldsAreInRange: Bool {
    switch self {
    case .midiNote(let channel, let note, let velocity):
      (1...16).contains(channel) && (0...Self.midiMaxData).contains(note)
        && (1...Self.midiMaxData).contains(velocity)
    case .midiControlChange(let channel, let controller):
      (1...16).contains(channel) && (0...Self.midiMaxData).contains(controller)
    default: true
    }
  }
}

extension RemappingProfile {
  /// Whether a destination of the profile sends MIDI.
  var usesMIDIOutput: Bool { containsDestination(where: \.isMIDI) }
}

extension RemappingEngineState {
  /// Whether any controller's profile sends MIDI.
  var usesMIDIOutput: Bool { devices.values.contains { $0.profile.usesMIDIOutput } }

  /// The control change that an axis value drives, or none while the value repeats the last one.
  ///
  /// A trigger rests at 0 and a stick at 64, which is where the last value starts, so a resting
  /// controller sends nothing. A stick value from -1 to 1 is shifted into 0 to 1.
  mutating func midiControlChange(
    _ binding: RemappingBinding,
    rawValue: Float,
    device: inout RemappingDeviceState
  ) -> [RemappingEngineAction] {
    guard let tuning = binding.axisTuning,
      case .midiControlChange(let channel, let controller) = binding.destination,
      case .axis(let axis) = binding.source
    else { return [] }
    let value = RemappingTransform.value(rawValue, tuning: tuning)
    let isTrigger = axis == .leftTrigger || axis == .rightTrigger
    let unit = min(max(isTrigger ? value : (value + 1) / 2, 0), 1)
    let scaled = Int((unit * Double(RemappingDestination.midiMaxData)).rounded())
    let last = device.outputs.midiValues[binding.id, default: isTrigger ? 0 : 64]
    guard scaled != last else { return [] }
    device.outputs.midiValues[binding.id] = scaled
    return [.midi(.controlChange(channel: channel, controller: controller, value: scaled))]
  }
}
