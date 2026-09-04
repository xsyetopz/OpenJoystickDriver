import Foundation
import Testing

@testable import OpenJoystickDriver

@Suite struct TerminateRelaunchPolicyTests {
  @Test func systemPermissionQuitRelaunches() {
    #expect(
      MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: false,
        signalInitiatedQuit: false,
        appleEventQuitReason: nil
      )
    )
  }

  @Test func menuQuitDoesNotRelaunch() {
    #expect(
      !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: true,
        signalInitiatedQuit: false,
        appleEventQuitReason: nil
      )
    )
  }

  @Test func shutdownSignalDoesNotRelaunch() {
    #expect(
      !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: false,
        signalInitiatedQuit: true,
        appleEventQuitReason: nil
      )
    )
  }

  @Test func sessionEndDoesNotRelaunch() {
    let reasons: [OSType] = [
      MenuBarTerminateRelaunchPolicy.logOutReason,
      MenuBarTerminateRelaunchPolicy.reallyLogOutReason,
      MenuBarTerminateRelaunchPolicy.shutDownReason,
      MenuBarTerminateRelaunchPolicy.restartReason,
    ]
    for reason in reasons {
      #expect(
        !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
          userInitiatedQuit: false,
          signalInitiatedQuit: false,
          appleEventQuitReason: reason
        )
      )
    }
  }
}
