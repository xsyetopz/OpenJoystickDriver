#if canImport(SwiftUI)

  import Testing

  @testable import OpenJoystickDriverPresentation

  /// A failed profile request shows beside the control that started it.
  @Suite
  @MainActor
  struct ProfileActionFailureTests {
    @Test
    func recoveryFailureShowsOnlyBesideRecoveryButton() {
      let screen = ProfilesViewModel()
      screen.failProfileAction("The library is locked.", beside: .recovery)
      #expect(screen.profileActionError(beside: .recovery) == "The library is locked.")
      #expect(screen.profileActionError(beside: .migration) == nil)
      #expect(screen.profileActionError(beside: .joyCon) == nil)
      #expect(screen.commandActionError == nil)
    }

    @Test
    func joyConFailureStaysOutOfCommandStrip() {
      let screen = ProfilesViewModel()
      screen.failProfileAction("No pair.", beside: .joyCon)
      #expect(screen.commandActionError == nil)
      #expect(screen.profileActionError == "No pair.")
    }

    @Test
    func commandFailureShowsInStripOnly() {
      let screen = ProfilesViewModel()
      screen.profileActionError = "Change running."
      #expect(screen.commandActionError == "Change running.")
      #expect(screen.profileActionError(beside: .recovery) == nil)
    }

    @Test
    func successClearsFailureAndNewFailureReplacesOrigin() {
      let screen = ProfilesViewModel()
      screen.failProfileAction("First.", beside: .migration)
      screen.failProfileAction("Second.", beside: .recovery)
      #expect(screen.profileActionError(beside: .migration) == nil)
      #expect(screen.profileActionError(beside: .recovery) == "Second.")
      screen.failProfileAction(nil, beside: .recovery)
      #expect(screen.profileActionError == nil)
    }
  }

#endif
