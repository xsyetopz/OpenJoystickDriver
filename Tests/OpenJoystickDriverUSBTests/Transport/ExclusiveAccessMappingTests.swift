import IOKit
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverUSB

struct ExclusiveAccessMappingTests {
  @Test
  func exclusiveAccessWithOwnerNamesOwner() {
    let owner = "pid 11070, steam_osx"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess, exclusiveOwner: owner)
        == .ownedByAnotherClient(owner: owner)
    )
  }

  @Test
  func exclusiveAccessWithoutOwnerCarriesNone() {
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess, exclusiveOwner: nil)
        == .ownedByAnotherClient(owner: nil)
    )
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnExclusiveAccess)
        == .ownedByAnotherClient(owner: nil)
    )
  }

  @Test
  func notPermittedStaysAccessDeniedWithoutOwner() {
    let owner = "pid 1, ignored"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnNotPermitted, exclusiveOwner: owner)
        == .accessDenied
    )
  }

  @Test
  func notPrivilegedStaysAccessDeniedWithoutOwner() {
    let owner = "pid 1, ignored"
    #expect(
      IOUSBHostTransportProvider.transportError(kIOReturnNotPrivileged, exclusiveOwner: owner)
        == .accessDenied
    )
  }

  /// On macOS 27 an interface that another process holds fails to open with
  /// `kIOReturnInternalError`; the owner the interface names is what says it is held.
  @Test
  func failedOpenOfInterfaceAnotherClientNamesIsOwnedByIt() {
    let owner = "pid 20887, hold"
    #expect(
      IOUSBHostTransportProvider.openError(
        kIOReturnInternalError,
        interfaceOwner: owner,
        processID: 1
      )
        == .ownedByAnotherClient(owner: owner)
    )
    #expect(
      IOUSBHostTransportProvider.openError(
        kIOReturnInternalError,
        interfaceOwner: nil,
        processID: 1
      )
        == .platform(
          code: kIOReturnInternalError,
          message: String(describing: kIOReturnInternalError)
        )
    )
    #expect(
      IOUSBHostTransportProvider.openError(
        kIOReturnInternalError,
        interfaceOwner: "pid 1, OpenJoystickDriv",
        processID: 1
      )
        == .platform(
          code: kIOReturnInternalError,
          message: String(describing: kIOReturnInternalError)
        )
    )
    #expect(
      IOUSBHostTransportProvider.openError(
        kIOReturnNotPermitted,
        interfaceOwner: owner,
        processID: 1
      )
        == .accessDenied
    )
  }
}
