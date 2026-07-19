import CoreFoundation
import Testing

@testable import OpenJoystickDriver

struct DriverKitRelayRequirementTests {
  @Test func exactRelayEntitlementRequiresDriverKitProof() {
    let access = ["com.openjoystickdriver.VirtualHIDDevice"] as CFArray

    #expect(DriverKitRelayRequirement.requiresRelay(userClientAccess: access))
  }

  @Test func absentOrUnrelatedEntitlementMakesRelayOptional() {
    let unrelated = ["com.example.UnrelatedDriver"] as CFArray

    #expect(!DriverKitRelayRequirement.requiresRelay(userClientAccess: nil))
    #expect(!DriverKitRelayRequirement.requiresRelay(userClientAccess: unrelated))
  }
}
