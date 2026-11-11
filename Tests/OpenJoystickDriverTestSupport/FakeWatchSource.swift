import Foundation

@testable package import OpenJoystickDriverKit

/// A ``ControllerWatchSource`` whose controllers a test sets; every controller reports one state.
package final class FakeWatchSource: ControllerWatchSource, @unchecked Sendable {
  package let output: ApplicationServiceVirtualOutputState = {
    var state = VirtualGamepadState()
    state.leftStickX = 100
    return ApplicationServiceVirtualOutputState(state)
  }()
  private let lock = NSLock()
  private var connected: [ApplicationServiceDeviceDescription] = []
  private var state = ControllerState()
  private var reads = 0
  private var order: [String] = []

  package var outputReads: Int { lock.withLock { reads } }
  /// `state` and `output`, one per read, in the order the reads came.
  package var readOrder: [String] { lock.withLock { order } }

  package init() {}

  package func set(devices ids: [String], state: ControllerState) {
    lock.withLock {
      connected = ids.map { ApplicationServiceDeviceDescription.fixture(id: $0) }
      self.state = state
    }
  }

  package func devices() -> [ApplicationServiceDeviceDescription] {
    lock.withLock { connected }
  }

  package func state(
    of _: ApplicationServiceDeviceDescription
  ) -> ControllerState? {
    lock.withLock {
      order.append("state")
      return state
    }
  }

  package func output(
    of _: ApplicationServiceDeviceDescription
  )
    -> ApplicationServiceVirtualOutputState?
  {
    lock.withLock {
      reads += 1
      order.append("output")
      return output
    }
  }
}
