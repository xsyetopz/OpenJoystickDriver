extension WiiDriver {
  /// The output report that carries speaker data.
  static let speakerDataOutputID: UInt8 = 0x18

  /// The plan for one speaker step: the setup script for `start`, a data packet for `data` and the
  /// stop script for `stop`.
  ///
  /// Each report carries the rumble bit. The steps go out together: the remote's acknowledgements
  /// are not awaited.
  func speakerPlan(_ output: SpeakerOutput) throws(ControllerOutputError) -> PhysicalOutputPlan {
    switch output {
    case .start(let seconds):
      guard seconds > 0, seconds <= Double(speakerMaxSeconds) else { throw .invalidValue }
      return PhysicalOutputPlan(writes: try wii.scripts.speaker.map(speakerWrite))
    case .stop: return PhysicalOutputPlan(writes: try wii.scripts.speakerStop.map(speakerWrite))
    case .data(let bytes):
      guard (1...WiiSpeakerStream.packetBytes).contains(bytes.count) else { throw .invalidValue }
      let padding = [UInt8](repeating: 0, count: WiiSpeakerStream.packetBytes - bytes.count)
      let header = [Self.speakerDataOutputID, UInt8(bytes.count << 3)]
      return PhysicalOutputPlan(writes: [outputReport(header + bytes + padding)])
    }
  }

  /// Builds the output write for one speaker protocol step.
  private func speakerWrite(
    _ step: ProtocolDescription.WiiRemote.Step
  ) throws(ControllerOutputError) -> PhysicalOutputWrite {
    switch step {
    case .report(let id, let data): return outputReport([id] + data)
    case .write(let address, let bytes): return registerWrite(address, bytes)
    default: throw .invalidValue
    }
  }
}
