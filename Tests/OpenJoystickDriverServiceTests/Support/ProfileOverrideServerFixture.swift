import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriverService

/// A server whose automatic dispatcher builds retarget probes and reads isolated overrides.
struct ProfileOverrideServerFixture {
  let server: ApplicationServiceServer
  let defaults: UserDefaults
  let suiteName: String
  let log: RetargetEventLog

  var store: VirtualHIDProfileOverrideStore { VirtualHIDProfileOverrideStore(defaults: defaults) }

  func change(
    _ change: ApplicationServiceServer.VirtualHIDProfileOverrideChange,
    vendorID: Int = 1,
    productID: Int = 2,
    runtimeIdentifier: String? = nil,
    unit: Bool = false
  ) async -> VirtualHIDProfileOverrideResult {
    await server.changeVirtualHIDProfileOverride(
      change,
      vendorID: vendorID,
      productID: productID,
      runtimeIdentifier: runtimeIdentifier,
      unit: unit
    )
  }

  func tearDown() async {
    await server.automaticUserSpaceDispatcher()?.close()
    defaults.removePersistentDomain(forName: suiteName)
  }
}

extension VirtualHIDProfileOverrideStore {
  func setGenericForTest() { try? set(.generic, vendorID: 1, productID: 2) }
}
