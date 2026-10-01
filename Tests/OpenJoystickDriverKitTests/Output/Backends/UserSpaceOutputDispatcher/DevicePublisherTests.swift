import Foundation
import IOKit
import IOKit.hid
import Testing

@testable import OpenJoystickDriverKit

final class RecordingDevicePublisher: VirtualHIDDevicePublisher, @unchecked Sendable {
  private let lock = NSLock()
  /// Returned in order; the last one is returned once the others are used.
  private var backends: [UserSpaceDispatcherTestBackend?]
  private var published: [(VirtualHIDDeviceDescription, VirtualHIDHostReports)] = []
  private var lostHandlers: [@Sendable () -> Void] = []

  init(backend: UserSpaceDispatcherTestBackend?) { backends = [backend] }

  init(backends: [UserSpaceDispatcherTestBackend]) { self.backends = backends }

  func publish(
    _ device: VirtualHIDDeviceDescription,
    hostReports: VirtualHIDHostReports,
    onLost: @escaping @Sendable () -> Void
  ) -> (any UserSpaceOutputDispatcher.VirtualDeviceBackend)? {
    lock.withLock {
      published.append((device, hostReports))
      lostHandlers.append(onLost)
      return backends.count > 1 ? backends.removeFirst() : backends.first.flatMap { $0 }
    }
  }

  func requests() -> [(VirtualHIDDeviceDescription, VirtualHIDHostReports)] {
    lock.withLock { published }
  }

  /// Reports the device of publish request `index` lost.
  func loseDevice(_ index: Int) { lock.withLock { lostHandlers[index] }() }
}

struct DevicePublisherTests {
  let identifier = DeviceIdentifier(vendorID: 1, productID: 2)

  @Test
  func publishedBackendReceivesTheDeviceAndItsDescriptionMatchesTheIOKitProperties() async throws {
    let published = UserSpaceDispatcherTestBackend()
    let publisher = RecordingDevicePublisher(backend: published)
    let fallback = LockedCounter()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in
        _ = fallback.next()
        return UserSpaceDispatcherTestBackend()
      },
      devicePublisher: publisher
    )

    try await dispatcher.activate(for: [identifier])

    #expect(fallback.current() == 0)
    #expect(published.counts().send == 1)
    let description = try #require(publisher.requests().first?.0)
    let properties = UserSpaceOutputDispatcher.deviceProperties(
      profile: .openJoystickDriverGenericHID,
      format: OJDGenericGamepadFormat(),
      identifier: identifier
    )
    #expect(Data(description.reportDescriptor) == properties[kIOHIDReportDescriptorKey] as? Data)
    #expect(Int(description.vendorID) == properties[kIOHIDVendorIDKey] as? Int)
    #expect(Int(description.productID) == properties[kIOHIDProductIDKey] as? Int)
    #expect(description.serialNumber == properties[kIOHIDSerialNumberKey] as? String)
    #expect(description.transport == properties[kIOHIDTransportKey] as? String)
    #expect(Int64(description.locationID) == properties[kIOHIDLocationIDKey] as? Int64)
    #expect(description.primaryUsagePage == UInt32(kHIDPage_GenericDesktop))
    #expect(description.primaryUsage == UInt32(kHIDUsage_GD_GamePad))

    await dispatcher.close()
    #expect(published.counts().close == 1)
  }

  @Test
  func hostReportsAnswerTheInputReportAndRejectMalformedRequests() async throws {
    let publisher = RecordingDevicePublisher(backend: UserSpaceDispatcherTestBackend())
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in UserSpaceDispatcherTestBackend() },
      devicePublisher: publisher
    )
    try await dispatcher.activate(for: [identifier])
    let hostReports = try #require(publisher.requests().first?.1)

    let input = hostReports.getReport(type: .input, reportID: 0, maxSize: 64)
    #expect(input.status == kIOReturnSuccess)
    #expect(input.bytes.count == OJDGenericGamepadFormat().inputReportPayloadSize)
    let empty = hostReports.getReport(type: .input, reportID: 0, maxSize: 0)
    #expect(empty.status == kIOReturnBadArgument)
    #expect(hostReports.setReport(type: .output, reportID: 0, bytes: []) != kIOReturnSuccess)

    await dispatcher.close()
    let closed = hostReports.getReport(type: .input, reportID: 0, maxSize: 64)
    #expect(closed.status == kIOReturnNotOpen)
  }

  @Test
  func declinedPublishFallsBackToTheNextBackend() async throws {
    let publisher = RecordingDevicePublisher(backend: nil)
    let fallback = UserSpaceDispatcherTestBackend()
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in fallback },
      devicePublisher: publisher
    )

    try await dispatcher.activate(for: [identifier])

    #expect(publisher.requests().count == 1)
    #expect(fallback.counts().send == 1)
    await dispatcher.close()
  }

  @Test
  func lostDeviceIsRepublishedWithItsLastStateWithoutNewInput() async throws {
    let first = UserSpaceDispatcherTestBackend()
    let second = UserSpaceDispatcherTestBackend()
    let publisher = RecordingDevicePublisher(backends: [first, second])
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in UserSpaceDispatcherTestBackend() },
      devicePublisher: publisher
    )
    await dispatcher.dispatch(changes: [.leftStick(x: 0.5, y: -0.25)], from: identifier)
    let moved = try #require(first.publishedReports().last)

    publisher.loseDevice(0)

    #expect(await eventually { second.publishedReports().first == moved })
    #expect(publisher.requests().count == 2)
    #expect(first.counts().close == 1)
    await dispatcher.close()
    #expect(second.counts().close == 1)
  }

  @Test
  func lossAfterTheControllerStoppedIsIgnored() async throws {
    let first = UserSpaceDispatcherTestBackend()
    let publisher = RecordingDevicePublisher(backends: [first, UserSpaceDispatcherTestBackend()])
    let dispatcher = UserSpaceOutputDispatcher(
      testBackendFactory: { _ in UserSpaceDispatcherTestBackend() },
      devicePublisher: publisher
    )
    try await dispatcher.activate(for: [identifier])
    await dispatcher.controllerDidStop(identifier)

    publisher.loseDevice(0)

    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(publisher.requests().count == 1)
    #expect(first.counts().close == 1)
    await dispatcher.close()
  }
}

/// Polls `condition` for up to two seconds.
private func eventually(_ condition: () async -> Bool) async -> Bool {
  for _ in 0..<200 {
    if await condition() { return true }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
  return await condition()
}
