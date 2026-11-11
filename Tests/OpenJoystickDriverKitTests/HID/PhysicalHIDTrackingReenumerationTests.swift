import Testing

@testable import OpenJoystickDriverKit

struct PhysicalHIDTrackingReenumerationTests {
  @Test
  func removalBeforeTheSuccessorDisconnects() {
    var hid = PhysicalHIDBackendEventAdapter()
    hid.add(deviceID: 1, locationID: 9, syntheticProperty: false, enumerationKey: "linked")
    #expect(hid.remove(deviceID: 1).shouldEmitDisconnect)
    hid.add(deviceID: 2, locationID: 9, syntheticProperty: false, enumerationKey: "idle")
    #expect(hid.isTracked(deviceID: 2))
  }

  @Test
  func removalAfterTheSuccessorDisconnects() {
    var hid = PhysicalHIDBackendEventAdapter()
    hid.add(deviceID: 1, locationID: 9, syntheticProperty: false, enumerationKey: "linked")
    hid.add(deviceID: 2, locationID: 9, syntheticProperty: false, enumerationKey: "idle")
    let removal = hid.remove(deviceID: 1)
    #expect(removal.shouldEmitDisconnect)
    #expect(!removal.locationRemoved)
    #expect(hid.acceptsInput(deviceID: 2))
    #expect(hid.remove(deviceID: 2).shouldEmitDisconnect)
  }

  @Test
  func aSuccessorWithAnotherSerialSupersedesTheEarlierDevice() {
    var hid = PhysicalHIDBackendEventAdapter()
    hid.add(deviceID: 1, locationID: 9, syntheticProperty: false, enumerationKey: "A1|pad")
    hid.add(deviceID: 2, locationID: 9, syntheticProperty: false, enumerationKey: "B2|pad")
    #expect(hid.remove(deviceID: 1).shouldEmitDisconnect)
  }

  @Test
  func siblingInterfacesOfOneEnumerationKeepTheLocationRule() {
    var hid = PhysicalHIDBackendEventAdapter()
    hid.add(deviceID: 1, locationID: 9, syntheticProperty: false, enumerationKey: "A1|pad")
    hid.add(deviceID: 2, locationID: 9, syntheticProperty: false, enumerationKey: "A1|pad")
    #expect(!hid.remove(deviceID: 1).shouldEmitDisconnect)
    #expect(hid.remove(deviceID: 2).shouldEmitDisconnect)
  }

  @Test
  func devicesWithoutAKeyKeepTheLocationRule() {
    var hid = PhysicalHIDBackendEventAdapter()
    hid.add(deviceID: 1, locationID: 9, syntheticProperty: false)
    hid.add(deviceID: 2, locationID: 9, syntheticProperty: false, enumerationKey: "idle")
    #expect(!hid.remove(deviceID: 1).shouldEmitDisconnect)
  }
}
