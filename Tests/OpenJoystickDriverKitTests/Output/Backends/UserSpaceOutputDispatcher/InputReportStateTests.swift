import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceInputReportStateTests {
  @Test func currentInputReportTracksChangesForHostGetReportRequests() throws {
    let format = try HIDDescriptorReportFormat(descriptor: XboxOneBluetoothHIDDescriptor.descriptor)
    let state = UserSpaceInputReportState(format: format)
    let neutral = state.currentReport()

    let active = state.update {
      $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.a.rawValue
      $0.leftStickX = 32_767
      $0.leftTrigger = 16_384
    }

    #expect(active != neutral)
    #expect(state.currentReport() == active)

    let released = state.update { $0 = VirtualGamepadState() }
    #expect(released == neutral)
    #expect(state.currentReport() == neutral)
  }
}
