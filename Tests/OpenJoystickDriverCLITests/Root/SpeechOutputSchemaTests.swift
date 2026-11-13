import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverCLI

/// The `Speak` destination in `Resources/Schemas/profile.schema.json`.
struct SpeechOutputSchemaTests {
  private static let original = #"{"type": "Keyboard", "key": "F5", "modifiers": []}"#

  private static func document(_ destination: String) -> String {
    ProfileSchemaTests.richDocument.replacingOccurrences(of: original, with: destination)
  }

  @Test
  func spokenPhraseWithOrWithoutVoiceIsAccepted() throws {
    for destination in [
      #"{"type": "Speak", "text": "Reloading"}"#,
      #"{"type": "Speak", "text": "Hi", "voice": "com.apple.voice.compact.en-US.Samantha"}"#,
    ] {
      #expect(try CLIOutputSchema.profileIssues(inJSON: Self.document(destination)).isEmpty)
    }
  }

  @Test
  func emptyTextEmptyVoiceAndTextOf129CharactersAreRejected() throws {
    let long = String(repeating: "a", count: 129)
    for destination in [
      #"{"type": "Speak", "text": ""}"#,
      #"{"type": "Speak", "text": "\#(long)"}"#,
      #"{"type": "Speak", "text": "Hi", "voice": ""}"#,
      #"{"type": "Speak"}"#,
    ] {
      #expect(try !CLIOutputSchema.profileIssues(inJSON: Self.document(destination)).isEmpty)
    }
  }
}
