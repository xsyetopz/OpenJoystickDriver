#if canImport(SwiftUI)

  import Combine
  import OpenJoystickDriverKit

  /// High-frequency input state is isolated from the lower-frequency session and output model so
  /// controller reports do not invalidate the complete Input Test window at the polling rate.
  @MainActor final class InputTestLiveState: ObservableObject {
    @Published private(set) var snapshot: DeviceInputState

    init(snapshot: DeviceInputState = DeviceInputState(vendorID: 0, productID: 0)) {
      self.snapshot = snapshot
    }

    func reset(vendorID: UInt16, productID: UInt16) {
      update(DeviceInputState(vendorID: vendorID, productID: productID))
    }

    func update(_ nextSnapshot: DeviceInputState) {
      guard snapshot != nextSnapshot else { return }
      snapshot = nextSnapshot
    }
  }

#endif
