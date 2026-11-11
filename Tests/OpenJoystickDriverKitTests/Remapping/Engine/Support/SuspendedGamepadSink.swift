import Foundation

@testable import OpenJoystickDriverKit

actor SuspendedGamepadSink: RemappingGamepadSink {
  private(set) var states: [RemappingGamepadState] = []
  private(set) var terminationCompleted = false
  private var suspended = false
  private var startedWaiter: CheckedContinuation<Void, Never>?
  private var sendWaiter: CheckedContinuation<Void, Never>?

  func send(_ state: RemappingGamepadState, for _: LogicalControllerID) async {
    states.append(state)
    guard !suspended else { return }
    suspended = true
    startedWaiter?.resume()
    startedWaiter = nil
    await withCheckedContinuation { sendWaiter = $0 }
  }

  func waitUntilSuspended() async {
    guard !suspended else { return }
    await withCheckedContinuation { startedWaiter = $0 }
  }

  func resumeSend() {
    sendWaiter?.resume()
    sendWaiter = nil
  }

  func markTerminationCompleted() { terminationCompleted = true }
}
