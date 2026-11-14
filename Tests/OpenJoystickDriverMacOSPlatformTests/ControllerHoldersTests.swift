import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct ControllerHoldersTests {
  /// The `ioreg` user clients of `2DC8:301C` during the 2C procedure: two Chrome clients, one each
  /// from WindowServer and OJD.
  @Test
  func eachProcessIsListedOnceInProcessOrder() {
    let holders = ControllerHolders.holders(
      creators: [
        "pid 812, Google Chrome He",
        "pid 412, WindowServer",
        "pid 812, Google Chrome He",
        "pid 1203, OpenJoystickDriv",
      ]
    ) { _ in nil }

    #expect(
      holders == [
        USBExclusiveOwner(processID: 412, name: "WindowServer"),
        USBExclusiveOwner(processID: 812, name: "Google Chrome He"),
        USBExclusiveOwner(processID: 1203, name: "OpenJoystickDriv"),
      ]
    )
  }

  /// The registry cuts a process name to 16 characters; a running process shows its full name.
  @Test
  func runningProcessShowsItsFullName() {
    let processID = ProcessInfo.processInfo.processIdentifier
    let fullName = ProcessInfo.processInfo.processName

    let holders = ControllerHolders.holders(creators: ["pid \(processID), \(fullName.prefix(4))"])

    #expect(holders == [USBExclusiveOwner(processID: processID, name: fullName)])
  }

  @Test
  func emptyCreatorNamesNoHolder() {
    #expect(ControllerHolders.holders(creators: ["", " "]).isEmpty)
  }

  @Test
  func absentControllerHasNoHolders() {
    #expect(
      ControllerHolders.holders(vendorID: 0xFFFF, productID: 0xFFFE, locationID: 0xFFFF_FFF0)
        .isEmpty
    )
  }
}
