import Foundation
import Testing

@testable import OpenJoystickDriver

@Suite struct TerminateRelaunchPolicyTests {
  private let application = URL(fileURLWithPath: "/Applications/OpenJoystickDriver.app")
  private let machO = URL(
    fileURLWithPath: "/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver"
  )

  @Test func permissionQuitAndReopenRelaunchesAfterExit() throws {
    let followUp = MenuBarTerminateRelaunchPolicy.followUp(
      userInitiatedQuit: false,
      signalInitiatedQuit: false,
      appleEventQuitReason: nil
    )
    #expect(followUp == .relaunch)
    #expect(
      MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: false,
        signalInitiatedQuit: false,
        appleEventQuitReason: nil
      )
    )
    let waiter = try #require(
      MenuBarTerminateRelaunchPolicy.terminateWaiter(
        parentProcessIdentifier: 42,
        bundleURL: application,
        followUp: followUp
      )
    )
    #expect(waiter.openAfterParentExits)
    #expect(waiter.interpreterPath == MenuBarTerminateRelaunchPolicy.waiterInterpreterPath)
    #expect(waiter.interpreterPath != application.path)
    #expect(waiter.interpreterPath != machO.path)
    #expect(waiter.openToolPath == "/usr/bin/open")
    #expect(waiter.openToolPath != machO.path)
    #expect(waiter.createsNewSession)
    #expect(waiter.parentProcessIdentifier == 42)
    #expect(waiter.bundleURL == application)
    #expect(waiter.bundleURL.pathExtension == "app")
    #expect(waiter.arguments.first == waiter.interpreterPath)
    #expect(waiter.arguments.contains(application.path))
    #expect(waiter.arguments.contains(waiter.openToolPath))
    #expect(!waiter.arguments.contains(machO.path))
    #expect(waiter.arguments.contains("42"))
    #expect(waiter.arguments.last == "1")
    #expect(
      MenuBarTerminateRelaunchPolicy.terminateWaiter(
        parentProcessIdentifier: 42,
        bundleURL: machO,
        followUp: followUp
      ) == nil
    )
  }

  @Test func genericAppleEventQuitRelaunchesAfterExit() {
    #expect(
      MenuBarTerminateRelaunchPolicy.followUp(
        userInitiatedQuit: false,
        signalInitiatedQuit: false,
        appleEventQuitReason: 0x6B616565
      ) == .relaunch
    )
  }

  @Test func menuQuitRetiresStaleJobWithoutRelaunch() throws {
    let followUp = MenuBarTerminateRelaunchPolicy.followUp(
      userInitiatedQuit: true,
      signalInitiatedQuit: false,
      appleEventQuitReason: nil
    )
    #expect(followUp == .retireStaleJob)
    #expect(
      !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: true,
        signalInitiatedQuit: false,
        appleEventQuitReason: nil
      )
    )
    let waiter = try #require(
      MenuBarTerminateRelaunchPolicy.terminateWaiter(
        parentProcessIdentifier: 42,
        bundleURL: application,
        followUp: followUp
      )
    )
    #expect(!waiter.openAfterParentExits)
    #expect(waiter.arguments.last == "0")
    #expect(waiter.arguments.contains(application.path))
    #expect(!waiter.arguments.contains(machO.path))
  }

  @Test func shutdownSignalRetiresStaleJobWithoutRelaunch() {
    let followUp = MenuBarTerminateRelaunchPolicy.followUp(
      userInitiatedQuit: false,
      signalInitiatedQuit: true,
      appleEventQuitReason: nil
    )
    #expect(followUp == .retireStaleJob)
    #expect(
      !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
        userInitiatedQuit: false,
        signalInitiatedQuit: true,
        appleEventQuitReason: nil
      )
    )
  }

  @Test func sessionEndDoesNotSpawnWaiter() {
    let reasons: [OSType] = [
      MenuBarTerminateRelaunchPolicy.logOutReason,
      MenuBarTerminateRelaunchPolicy.reallyLogOutReason,
      MenuBarTerminateRelaunchPolicy.shutDownReason,
      MenuBarTerminateRelaunchPolicy.restartReason,
    ]
    for reason in reasons {
      #expect(
        MenuBarTerminateRelaunchPolicy.followUp(
          userInitiatedQuit: false,
          signalInitiatedQuit: false,
          appleEventQuitReason: reason
        ) == .none
      )
      #expect(
        !MenuBarTerminateRelaunchPolicy.shouldRelaunch(
          userInitiatedQuit: false,
          signalInitiatedQuit: false,
          appleEventQuitReason: reason
        )
      )
      #expect(
        MenuBarTerminateRelaunchPolicy.terminateWaiter(
          parentProcessIdentifier: 42,
          bundleURL: application,
          followUp: .none
        ) == nil
      )
    }
  }
}
