import AVFoundation
import OpenJoystickDriverKit

/// Speaks `Speak` destinations through `AVSpeechSynthesizer`, one synthesizer per controller.
public final class AVSpeechOutput: RemappingSpeechOutput, @unchecked Sendable {
  /// The synthesizers by controller; touched on the main actor only.
  @MainActor
  private var synthesizers: [LogicalControllerID: AVSpeechSynthesizer] = [:]

  /// Creates an output that has spoken nothing yet.
  public init() {}

  /// Stops what the controller is saying and speaks `text` from the start.
  public func speak(_ text: String, voice: String?, for identifier: LogicalControllerID) async {
    await MainActor.run {
      let synthesizer = synthesizers[identifier] ?? AVSpeechSynthesizer()
      synthesizers[identifier] = synthesizer
      synthesizer.stopSpeaking(at: .immediate)
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = voice.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
      synthesizer.speak(utterance)
    }
  }

  /// Stops what the controller is saying at once.
  public func stopSpeech(for identifier: LogicalControllerID) async {
    await MainActor.run {
      _ = synthesizers[identifier]?.stopSpeaking(at: .immediate)
    }
  }

  /// Whether this Mac has the voice.
  public func hasVoice(_ identifier: String) -> Bool {
    AVSpeechSynthesisVoice(identifier: identifier) != nil
  }
}
