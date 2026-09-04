import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceInputReportStateTests {
  @Test func currentInputReportTracksChangesForHostGetReportRequests() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.seriesDescriptor
    )
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

  @Test func genericCompatibilityTriggersReturnToTheirExactPreActuationReport() {
    let format = OJDSDLGamepadFormat()
    let firstSession = UserSpaceInputReportState(format: format)
    let neutral = firstSession.currentReport()

    let actuated = firstSession.update {
      $0.leftTrigger = 32_767
      $0.rightTrigger = 32_767
    }
    let released = firstSession.update {
      $0.leftTrigger = 0
      $0.rightTrigger = 0
    }
    let recreatedSession = UserSpaceInputReportState(format: format)

    #expect(actuated != neutral)
    #expect(released == neutral)
    #expect(recreatedSession.currentReport() == neutral)
    #expect(Array(neutral[6...7]) == [0, 0])
    #expect(Array(neutral[12...13]) == [0, 0])
  }

  @Test func appleCompatibilityTracksShareSeparatelyFromView() throws {
    let format = try HIDDescriptorReportFormat(
      descriptor: XboxOneBluetoothHIDDescriptor.seriesDescriptor,
      buttonUsageMap: XboxOneBluetoothHIDDescriptor.buttonUsageMap,
      digitalUsageMap: XboxOneBluetoothHIDDescriptor.seriesDigitalUsageMap
    )
    let state = UserSpaceInputReportState(format: format)
    let neutral = state.currentReport()

    let share = state.update { $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.share.rawValue }
    let view = state.update { $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.back.rawValue }

    #expect(share[14] == 0)
    #expect(share[16] == 1)
    #expect(view[14] == 0x40)
    #expect(view[16] == 0)
    #expect(state.update { $0 = VirtualGamepadState() } == neutral)
  }
}
