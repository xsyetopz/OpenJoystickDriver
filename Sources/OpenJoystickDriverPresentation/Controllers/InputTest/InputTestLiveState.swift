#if canImport(SwiftUI)

  import Combine
  import OpenJoystickDriverKit

  /// High-frequency input state is isolated from the lower-frequency session and output model so
  /// controller reports do not invalidate the complete Input Test window at the polling rate.
  @MainActor
  final class InputTestLiveState: ObservableObject {
    /// The latest input of the controller.
    @Published
    private(set) var snapshot: ControllerState

    /// Creates the state on `snapshot`.
    ///
    /// - Parameter snapshot: The input to start with; neutral by default.
    init(snapshot: ControllerState = .neutral) {
      self.snapshot = snapshot
    }

    /// Sets the input to neutral.
    func reset() {
      update(.neutral)
    }

    /// Replaces the input with `nextSnapshot` unless it is equal.
    ///
    /// - Parameter nextSnapshot: The latest input.
    func update(_ nextSnapshot: ControllerState) {
      guard snapshot != nextSnapshot else { return }
      snapshot = nextSnapshot
    }
  }

#endif
