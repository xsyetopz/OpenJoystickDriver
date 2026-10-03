import Foundation

@testable import OpenJoystickDriverKit

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

  package var outputReads: Int { lock.withLock { reads } }

  package init() {}

  package func set(devices ids: [String], state: ControllerState) {
    lock.withLock {
      connected = ids.map { ApplicationServiceDeviceDescription.fixture(id: $0) }
      self.state = state
    }
  }

  package func devices() throws -> [ApplicationServiceDeviceDescription] {
    lock.withLock { connected }
  }

  package func state(
    of device: ApplicationServiceDeviceDescription
  ) throws -> ControllerState? {
    lock.withLock { state }
  }

  package func output(
    of device: ApplicationServiceDeviceDescription
  ) throws
    -> ApplicationServiceVirtualOutputState?
  {
    lock.withLock {
      reads += 1
      return output
    }
  }
}
