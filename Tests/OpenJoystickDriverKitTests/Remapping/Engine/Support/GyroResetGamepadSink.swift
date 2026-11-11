import Foundation

@testable import OpenJoystickDriverKit

actor GyroResetGamepadSink: RemappingGamepadSink {
  private(set) var states: [RemappingGamepadState] = []
  private var rejectNext = false

  func rejectNextSend() { rejectNext = true }

  func send(_ state: RemappingGamepadState, for _: LogicalControllerID) throws {
    if rejectNext {
      rejectNext = false
      throw RemappingEventEngineError.sinkUnavailable
    }
    states.append(state)
  }
}
