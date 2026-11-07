import Foundation

extension DeviceManager {
  /// Plays `audio`, bytes in the speaker's format, on the speaker of the controller `controller`
  /// names, and returns when the clip ends or `stopSpeaker(for:)` cuts it.
  ///
  /// A second clip on the same controller replaces the first.
  public func playSpeaker(
    _ audio: Data,
    for controller: ControllerReference
  ) async -> ControllerOutputResult {
    guard let key = connectedIdentifier(for: controller), !isStopping, let pipeline = pipelines[key]
    else { return ControllerOutputResult(.notFound) }
    guard let format = await pipeline.physicalOutputCapabilities().speaker else {
      return ControllerOutputResult(.unsupportedCapability)
    }
    speakerTasks[key]?.cancel()
    let seconds = Double(audio.count * 2) / Double(format.sampleRate)
    let started = await sendSpeaker(.start(seconds: seconds), key, pipeline)
    guard started == .delivered else { return ControllerOutputResult(started) }
    let task = Task { await self.stream(audio, at: format.sampleRate, key, pipeline) }
    speakerTasks[key] = task
    let outcome = await task.value
    if !task.isCancelled { speakerTasks[key] = nil }
    return ControllerOutputResult(outcome)
  }

  /// Cuts the clip playing on the controller `controller` names and mutes its speaker.
  public func stopSpeaker(for controller: ControllerReference) async -> ControllerOutputResult {
    guard let key = connectedIdentifier(for: controller), !isStopping, let pipeline = pipelines[key]
    else { return ControllerOutputResult(.notFound) }
    guard await pipeline.physicalOutputCapabilities().supportsSpeaker else {
      return ControllerOutputResult(.unsupportedCapability)
    }
    speakerTasks.removeValue(forKey: key)?.cancel()
    return ControllerOutputResult(await sendSpeaker(.stop, key, pipeline))
  }

  /// Sends one speaker output to the controller behind `key` through `pipeline`.
  private func sendSpeaker(
    _ output: SpeakerOutput,
    _ key: LogicalControllerID,
    _ pipeline: DevicePipeline
  ) async -> ControllerOutputResult.Outcome {
    await sendPhysicalOutput(.command(.speaker(output)), for: key, pipeline: pipeline)
  }

  /// Sends the packets at the speaker's rate, then stops the speaker unless the task was
  /// cancelled.
  private func stream(
    _ audio: Data,
    at rate: Int,
    _ key: LogicalControllerID,
    _ pipeline: DevicePipeline
  ) async -> ControllerOutputResult.Outcome {
    var stream = WiiSpeakerStream(encoded: Array(audio), rate: rate)
    while !stream.isFinished, !Task.isCancelled {
      let now = MonotonicTimestamp(nanoseconds: DispatchTime.now().uptimeNanoseconds)
      for packet in stream.due(at: now) {
        let outcome = await sendSpeaker(.data(packet), key, pipeline)
        guard outcome == .delivered else { return outcome }
      }
      guard let next = stream.nextDue else { break }
      let current = DispatchTime.now().uptimeNanoseconds
      try? await Task.sleep(nanoseconds: max(next.nanoseconds, current) - current)
    }
    return Task.isCancelled ? .cancelled : await sendSpeaker(.stop, key, pipeline)
  }
}
