import Testing

@testable import OpenJoystickDriverPresentation

struct SemanticStatePresentationTests {
  @Test
  func everyStateHasRequiredToneAndNonColorSignal() {
    let expected: [SemanticState: SemanticTone] = [
      .active: .positive, .healthy: .positive, .attention: .attention, .failure: .failure,
      .inactive: .neutral, .loading: .neutral, .disconnected: .neutral, .unknown: .neutral,
      .dirty: .attention, .saved: .positive, .capturing: .positive,
    ]

    #expect(Set(expected.keys) == Set(SemanticState.allCases))
    for state in SemanticState.allCases {
      #expect(state.presentation.tone == expected[state])
      #expect(!state.presentation.symbolName.isEmpty)
    }
  }

  @Test
  func attentionOrangeTriangleFailureRedOctagon() {
    #expect(SemanticState.attention.presentation.tone == .attention)
    #expect(SemanticState.attention.presentation.symbolName == "exclamationmark.triangle")
    #expect(SemanticState.failure.presentation.tone == .failure)
    #expect(SemanticState.failure.presentation.symbolName == "xmark.octagon")
  }

  @Test
  func symbolResolutionUsesSupportedSymbolThenLocalizedText() {
    #expect(
      SystemSymbolPolicy.resolution(
        preferred: "preferred",
        fallback: "fallback",
        preferredIsAvailable: true,
        fallbackIsAvailable: true
      ) == .symbol("preferred")
    )
    #expect(
      SystemSymbolPolicy.resolution(
        preferred: "preferred",
        fallback: "fallback",
        preferredIsAvailable: false,
        fallbackIsAvailable: true
      ) == .symbol("fallback")
    )
    #expect(
      SystemSymbolPolicy.resolution(
        preferred: "preferred",
        fallback: "fallback",
        preferredIsAvailable: false,
        fallbackIsAvailable: false
      ) == .text
    )
  }

  @Test
  func saveStatesUseSharedSemanticContract() {
    #expect(ProfileSaveStatus.unsaved.semanticState == .dirty)
    #expect(ProfileSaveStatus.saving.semanticState == .loading)
    #expect(ProfileSaveStatus.saved.semanticState == .saved)
    #expect(ProfileSaveStatus.error.semanticState == .failure)
  }
}
