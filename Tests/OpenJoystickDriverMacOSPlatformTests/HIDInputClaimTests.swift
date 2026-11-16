import IOKit
import IOKit.hid
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverMacOSPlatform

/// A device object that records its open and close calls and answers them from scripts.
private final class RecordingPort: @unchecked Sendable {
  enum Call: Equatable {
    case open(IOOptionBits)
    case close(IOOptionBits)
  }

  var calls: [Call] = []
  var openResults: [IOOptionBits: IOReturn]
  var closeResult: IOReturn = kIOReturnSuccess

  init(seize: IOReturn = kIOReturnSuccess, shared: IOReturn = kIOReturnSuccess) {
    openResults = [
      IOOptionBits(kIOHIDOptionsTypeSeizeDevice): seize,
      IOOptionBits(kIOHIDOptionsTypeNone): shared,
    ]
  }

  var port: HIDDeviceOpenPort {
    HIDDeviceOpenPort(
      open: { options in
        self.calls.append(.open(options))
        return self.openResults[options] ?? kIOReturnError
      },
      close: { options in
        self.calls.append(.close(options))
        return self.closeResult
      }
    )
  }
}

private let seize = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
private let shared = IOOptionBits(kIOHIDOptionsTypeNone)

struct HIDInputClaimTests {
  /// A second open from one client is ignored by the kernel and reports success, so a seize that
  /// follows a shared open is never granted.
  ///
  /// The seize is the only open of the device object.
  @Test
  func seizeIsFirstAndOnlyOpen() {
    let recorder = RecordingPort()
    let claim = HIDInputClaim.admit(port: recorder.port, seize: true)

    #expect(recorder.calls == [.open(seize)])
    #expect(claim.seized)
    #expect(claim.ownership == .exclusive)
    #expect(claim.inputResult == kIOReturnSuccess)
  }

  @Test
  func deviceThatIsNotSeizedOpensSharedWithoutOwnership() {
    let recorder = RecordingPort()
    let claim = HIDInputClaim.admit(port: recorder.port, seize: false)

    #expect(recorder.calls == [.open(shared)])
    #expect(!claim.seized)
    #expect(claim.ownership == nil)
  }

  @Test(
    arguments: [
      (kIOReturnExclusiveAccess, HIDInputOwnership.ownedByAnotherClient),
      (kIOReturnNotPermitted, .accessDenied),
      (kIOReturnNotPrivileged, .accessDenied),
      (kIOReturnError, .acquisitionFailed),
    ]
  )
  func refusedSeizeNamesItsOwnershipAndNeverReportsExclusive(
    result: IOReturn,
    expected: HIDInputOwnership
  ) {
    let recorder = RecordingPort(seize: result)
    let claim = HIDInputClaim.admit(port: recorder.port, seize: true)

    #expect(!claim.seized)
    #expect(claim.ownership == expected)
    #expect(claim.seizeResult == result)
    // The refused client leaves the device before the shared open.
    #expect(recorder.calls == [.open(seize), .close(seize), .open(shared)])
  }

  @Test
  func refusedSeizeKeepsSharedOpenResultAsInputResult() {
    let recorder = RecordingPort(seize: kIOReturnNotPrivileged, shared: kIOReturnNotPermitted)
    let claim = HIDInputClaim.admit(port: recorder.port, seize: true)

    #expect(claim.inputResult == kIOReturnNotPermitted)
  }

  @Test
  func reclaimingClosesSharedOpenBeforeSeize() {
    let recorder = RecordingPort()
    let claim = HIDInputClaim.reclaim(port: recorder.port)

    #expect(recorder.calls == [.close(shared), .open(seize)])
    #expect(claim.seized)
  }

  @Test
  func refusedReclaimRestoresSharedOpen() {
    let recorder = RecordingPort(seize: kIOReturnExclusiveAccess)
    let claim = HIDInputClaim.reclaim(port: recorder.port)

    #expect(recorder.calls == [.close(shared), .open(seize), .close(seize), .open(shared)])
    #expect(claim.ownership == .ownedByAnotherClient)
    #expect(claim.inputResult == kIOReturnSuccess)
  }

  @Test
  func releasingClosesSeizeThenOpensShared() {
    let recorder = RecordingPort()

    #expect(HIDInputClaim.release(port: recorder.port) == kIOReturnSuccess)
    #expect(recorder.calls == [.close(seize), .open(shared)])
  }

  @Test
  func failedReleaseCloseStopsBeforeSharedOpen() {
    let recorder = RecordingPort()
    recorder.closeResult = kIOReturnNotOpen

    #expect(HIDInputClaim.release(port: recorder.port) == kIOReturnNotOpen)
    #expect(recorder.calls == [.close(seize)])
  }
}
