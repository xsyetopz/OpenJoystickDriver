import ProtocolPacketFixtures
import Testing

@testable import OpenJoystickDriverKit

struct UserSpaceInputReportStateTests {
  @Test
  func currentInputReportTracksChangesForHostGetReportRequests() {
    let state = UserSpaceInputReportState(format: XboxOneGIPHIDReportFormat())
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

  @Test
  func xboxOneGIPIdleReportMatchesInterruptGetReportLayout() {
    let format = XboxOneGIPHIDReportFormat()
    let report = UserSpaceInputReportState(format: format).currentReport()
    #expect(report == ProtocolPacketFixtures.XboxOneGIP.neutralInputReport)
  }

  @Test
  func guideChangesClaimTheSeparateGuideReportOnce() {
    let state = UserSpaceInputReportState(format: XboxOneGIPHIDReportFormat())
    #expect(state.claimChangedAuxiliaryReports().isEmpty)

    _ = state.update { $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.guide.rawValue }
    #expect(state.claimChangedAuxiliaryReports() == [[0x07, 0x20, 0x00, 0x02, 1, 0x5B]])
    #expect(state.claimChangedAuxiliaryReports().isEmpty)

    _ = state.update { $0 = VirtualGamepadState() }
    #expect(state.claimChangedAuxiliaryReports() == [[0x07, 0x20, 0x00, 0x02, 0, 0x5B]])
  }

  @Test
  func genericVirtualOutputTriggersReturnToTheirExactPreActuationReport() {
    let format = OJDGenericGamepadFormat()
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
    #expect((neutral[0] & 0xC0) == 0)
  }

  @Test
  func xboxOneGIPNeverSetsShareAndKeepsViewOnItsButton() {
    let format = XboxOneGIPHIDReportFormat()
    let state = UserSpaceInputReportState(format: format)
    let neutral = state.currentReport()

    let share = state.update { $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.share.rawValue }
    let view = state.update { $0.buttons = 1 << GamepadHIDDescriptor.ButtonBit.back.rawValue }

    #expect(share == neutral)
    #expect(view[4] == 0x08)
    #expect(view[5] == 0)
    #expect(state.update { $0 = VirtualGamepadState() } == neutral)
  }

  @Test
  func everyVirtualHIDProfileFormatPreservesCompoundStateAcrossUpdatesAndRelease() {
    for profile in VirtualHIDProfileID.allCases {
      let format = profile.makeProfile().reportFormat
      let reportState = UserSpaceInputReportState(format: format)
      let neutral = reportState.currentReport()
      var expected = compoundState()

      let active = reportState.update { $0 = expected }
      #expect(active == format.buildInputReport(from: expected), "\(profile)")
      #expect(active != neutral, "\(profile)")

      expected.rightStickX = 12_345
      let updated = reportState.update { $0.rightStickX = expected.rightStickX }
      #expect(updated == format.buildInputReport(from: expected), "\(profile)")

      let released = reportState.update { $0 = VirtualGamepadState() }
      #expect(released == neutral, "\(profile)")
    }
  }

  @Test
  func everyVirtualHIDProfileFormatExplicitlyClassifiesSpecialControlSupport() {
    let supported: [VirtualHIDProfileID: Set<SpecialControl>] = [
      .sdlCompatible: [], .generic: [.share], .gameControllerCompatible: [.share],
    ]
    #expect(Set(supported.keys) == Set(VirtualHIDProfileID.allCases))

    for profile in VirtualHIDProfileID.allCases {
      let format = profile.makeProfile().reportFormat
      let neutral = format.buildInputReport(from: VirtualGamepadState())
      let supportedControls = supported[profile] ?? []
      for control in SpecialControl.allCases {
        var state = VirtualGamepadState()
        switch control {
        case .share: state.buttons = 1 << GamepadHIDDescriptor.ButtonBit.share.rawValue
        }
        #expect(
          (format.buildInputReport(from: state) != neutral) == supportedControls.contains(control),
          "\(profile) \(control)"
        )
      }
    }
  }

  private func compoundState() -> VirtualGamepadState {
    VirtualGamepadState(
      buttons: UInt32.max,
      leftStickX: 24_000,
      leftStickY: -20_000,
      rightStickX: -16_000,
      rightStickY: 8_000,
      leftTrigger: 24_000,
      rightTrigger: 12_000,
      leftTriggerPressed: true,
      rightTriggerPressed: true,
      hat: .southWest
    )
  }
}

/// A control that only some virtual HID report formats carry.
private enum SpecialControl: CaseIterable { case share }
