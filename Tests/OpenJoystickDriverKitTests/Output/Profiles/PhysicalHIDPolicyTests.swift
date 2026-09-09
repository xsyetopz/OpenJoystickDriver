import Dispatch
import Foundation
import Testing

@testable import OpenJoystickDriverKit

private final class RemovalDecisionRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var decisions: [PhysicalHIDBackendEventAdapter.RemovalDecision] = []

  func reset() { lock.withLock { decisions.removeAll() } }

  func append(_ decision: PhysicalHIDBackendEventAdapter.RemovalDecision) {
    lock.withLock { decisions.append(decision) }
  }

  func disconnectCount() -> Int { lock.withLock { decisions.filter(\.shouldEmitDisconnect).count } }
}

struct PhysicalHIDPolicyTests {
  @Test func testSyntheticAppleGameControllerDevicesAreExcluded() {
    #expect(UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(true))
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(false))
    var numericValue: Int32 = 1
    let numeric = withUnsafePointer(to: &numericValue) { CFNumberCreate(nil, .sInt32Type, $0) }
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(numeric))
    #expect(!UserSpaceVirtualDeviceConstants.isAppleGameControllerSyntheticDevice(nil))
  }

  @Test func physicalHIDAdmissionRejectsEveryIndependentVirtualDeviceMarker() {
    let physicalLocation: UInt32 = 1_114_112
    let virtualLocation = UserSpaceVirtualDeviceConstants.locationID(
      for: DeviceIdentifier(vendorID: 0x3537, productID: 0x1010, locationID: physicalLocation)
    )

    func accepts(
      serialNumber: String? = "physical-serial",
      productName: String? = "GameSir-G7 SE Controller for Xbox",
      transport: String? = "USB",
      locationID: UInt32 = physicalLocation,
      syntheticProperty: Any? = kCFBooleanFalse
    ) -> Bool {
      PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: serialNumber,
        productName: productName,
        transport: transport,
        locationID: locationID,
        syntheticProperty: syntheticProperty
      )
    }

    #expect(accepts())
    #expect(!accepts(serialNumber: UserSpaceVirtualDeviceConstants.serialPrefix + "opaque"))
    #expect(!accepts(productName: UserSpaceVirtualDeviceConstants.product))
    #expect(!accepts(transport: "Virtual"))
    #expect(!accepts(transport: "virtual"))
    #expect(!accepts(locationID: virtualLocation))
    #expect(!accepts(syntheticProperty: kCFBooleanTrue))
    #expect(accepts(productName: "GamePad-1", syntheticProperty: nil))
  }

  @Test func compatibilitySpoofRemainsExcludedWhenAppleOmitsSerialAndSyntheticProperties() {
    let physical = DeviceIdentifier(
      vendorID: 0x3537,
      productID: 0x1010,
      serialNumber: "physical-serial",
      locationID: 1_114_112
    )
    let virtualLocation = UserSpaceVirtualDeviceConstants.locationID(for: physical)

    #expect(
      !PhysicalHIDBackendEventPolicy.acceptsDevice(
        serialNumber: nil,
        productName: "Xbox One S Controller",
        transport: "Bluetooth",
        locationID: virtualLocation,
        syntheticProperty: nil
      )
    )
  }

  @Test func syntheticFilteringPolicyCoversEveryPhysicalHIDBoundary() {
    let events: [UserSpaceVirtualDeviceConstants.PhysicalHIDEvent] = [
      .deviceAdded, .inputReport, .inputValue, .deviceRemoved, .descriptorDiscovery, .feedback
    ]
    for event in events {
      #expect(
        !UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent(
          event,
          syntheticProperty: kCFBooleanTrue
        )
      )
      #expect(
        UserSpaceVirtualDeviceConstants.acceptsPhysicalHIDEvent(
          event,
          syntheticProperty: kCFBooleanFalse
        )
      )
    }
  }

  @Test func physicalHIDTrackingEngineModelsSyntheticAndPhysicalEventSequences() {
    var engine = PhysicalHIDTrackingStateMachine()
    var disconnectCount = 0
    let synthetic = engine.register(deviceID: 1, locationID: 101, syntheticProperty: kCFBooleanTrue)
    #expect(!synthetic)
    #expect(!engine.acceptsInput(deviceID: 1))
    #expect(!engine.acceptsFeedback(locationID: 101))
    let syntheticRemoval = engine.remove(deviceID: 1)
    #expect(!syntheticRemoval)

    let physicalRegistration = engine.register(
      deviceID: 2,
      locationID: 202,
      syntheticProperty: kCFBooleanFalse
    )
    #expect(physicalRegistration)
    #expect(engine.acceptsInput(deviceID: 2))
    #expect(engine.acceptsInput(locationID: 202))
    #expect(engine.acceptsFeedback(locationID: 202))
    let physicalRemoval = engine.remove(deviceID: 2)
    if physicalRemoval { disconnectCount += 1 }
    #expect(!engine.acceptsInput(locationID: 202))
    #expect(!engine.acceptsFeedback(locationID: 202))
    let staleRemoval = engine.remove(deviceID: 2)
    #expect(!staleRemoval)
    if staleRemoval { disconnectCount += 1 }
    #expect(disconnectCount == 1)
  }

  @Test func bothProductionBackendsUseTheCentralSyntheticPolicy() {
    let events: [UserSpaceVirtualDeviceConstants.PhysicalHIDEvent] = [
      .deviceAdded, .inputReport, .inputValue, .deviceRemoved, .descriptorDiscovery, .feedback
    ]
    for event in events {
      #expect(
        PhysicalHIDBackendEventPolicy.accepts(event, syntheticProperty: kCFBooleanTrue) == false
      )
      #expect(PhysicalHIDBackendEventPolicy.accepts(event, syntheticProperty: kCFBooleanFalse))
    }
  }

  @Test func productionBackendAdaptersRejectSyntheticSharedLocationAndCleanPhysicalState() {
    var ioHID = PhysicalHIDBackendEventAdapter()
    var coreHID = PhysicalHIDBackendEventAdapter()

    for adapter in [ioHID, coreHID] {
      var adapter = adapter
      let syntheticAdded = adapter.add(
        deviceID: 2,
        locationID: 77,
        syntheticProperty: kCFBooleanTrue
      )
      #expect(!syntheticAdded)
      #expect(!adapter.acceptsInput(deviceID: 2))
      #expect(!adapter.acceptsFeedback(locationID: 77))
      #expect(!adapter.remove(deviceID: 2).wasTracked)
    }

    let physicalAdded = ioHID.add(deviceID: 1, locationID: 77, syntheticProperty: kCFBooleanFalse)
    let syntheticAdded = ioHID.add(deviceID: 2, locationID: 77, syntheticProperty: kCFBooleanTrue)
    #expect(physicalAdded)
    #expect(!syntheticAdded)
    #expect(ioHID.acceptsInput(deviceID: 1))
    #expect(!ioHID.acceptsInput(deviceID: 2))
    #expect(ioHID.acceptsFeedback(locationID: 77))
    let rejectedRemoval = ioHID.remove(deviceID: 2)
    #expect(!rejectedRemoval.wasTracked)
    let physicalRemoval = ioHID.remove(deviceID: 1)
    #expect(physicalRemoval.wasTracked)
    #expect(physicalRemoval.shouldCancelNotification)
    #expect(physicalRemoval.shouldEmitDisconnect)
    #expect(!ioHID.acceptsFeedback(locationID: 77))
    #expect(!ioHID.remove(deviceID: 1).shouldEmitDisconnect)

    let coreAdded = coreHID.add(deviceID: 1, locationID: 77, syntheticProperty: kCFBooleanFalse)
    #expect(coreAdded)
    let coreRemoval = coreHID.remove(deviceID: 1)
    #expect(coreRemoval.wasTracked)
    #expect(coreRemoval.shouldCancelNotification)
    #expect(coreRemoval.shouldEmitDisconnect)
  }

  @Test func synchronizedProductionAdapterSerializesConcurrentLifecycleAndFeedback() {
    let holder = SynchronizedPhysicalHIDBackendEventAdapter()
    let recorder = RemovalDecisionRecorder()

    for iteration in 0..<100 {
      holder.reset()
      let added = holder.add(
        deviceID: 1,
        locationID: UInt32(iteration),
        syntheticProperty: kCFBooleanFalse
      )
      #expect(added)
      recorder.reset()
      DispatchQueue.concurrentPerform(iterations: 64) { index in
        switch index % 4 {
        case 0: _ = holder.acceptsInput(deviceID: 1)
        case 1: _ = holder.acceptsFeedback(locationID: UInt32(iteration))
        case 2:
          let decision = holder.remove(deviceID: 1)
          recorder.append(decision)
        default: _ = holder.acceptsDescriptor(syntheticProperty: kCFBooleanFalse)
        }
      }

      #expect(recorder.disconnectCount() == 1)
      #expect(!holder.acceptsInput(deviceID: 1))
      #expect(!holder.acceptsFeedback(locationID: UInt32(iteration)))
    }

    DispatchQueue.concurrentPerform(iterations: 128) { index in
      if index.isMultiple(of: 5) {
        holder.reset()
      } else if index % 5 == 1 {
        _ = holder.add(
          deviceID: UInt64(index + 10),
          locationID: 999,
          syntheticProperty: kCFBooleanFalse
        )
      } else if index % 5 == 2 {
        _ = holder.acceptsInput(deviceID: UInt64(index + 10))
      } else if index % 5 == 3 {
        _ = holder.acceptsFeedback(locationID: 999)
      } else {
        _ = holder.remove(deviceID: UInt64(index + 10))
      }
    }
    holder.reset()
    #expect(!holder.acceptsInput(deviceID: 10))
    #expect(!holder.acceptsFeedback(locationID: 999))
  }

}
