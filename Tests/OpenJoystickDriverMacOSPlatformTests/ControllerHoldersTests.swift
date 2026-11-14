import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverMacOSPlatform

struct ControllerHoldersTests {
  /// The `ioreg` user clients of `2DC8:301C` during the 2C procedure: two Chrome clients, one each
  /// from WindowServer and OJD.
  @Test
  func eachProcessIsListedOnceInProcessOrder() {
    let holders = ControllerHolders.holders(creators: [
      "pid 812, Google Chrome He",
      "pid 412, WindowServer",
      "pid 812, Google Chrome He",
      "pid 1203, OpenJoystickDriv",
    ])

    #expect(
      holders == [
        USBExclusiveOwner(processID: 412, name: "WindowServer"),
        USBExclusiveOwner(processID: 812, name: "Google Chrome He"),
        USBExclusiveOwner(processID: 1203, name: "OpenJoystickDriv"),
      ]
    )
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
