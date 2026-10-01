import Foundation
import IOKit
import OpenJoystickDriverKit
import SwifterKit
import Testing

@testable import OpenJoystickDriverUSB

final class FakeHIDFactoryConnection: HIDFactoryConnection, @unchecked Sendable {
  let events: AsyncStream<HIDFactoryEvent>
  let continuation: AsyncStream<HIDFactoryEvent>.Continuation
  private let lock = NSLock()
  private var createResults: [Result<UInt32, HIDFactoryStatusError>]
  private var created = 0
  private var terminated: [UInt32] = []
  private var inputs: [(UInt32, [UInt8])] = []

  init(createResults: [Result<UInt32, HIDFactoryStatusError>]) {
    self.createResults = createResults
    (events, continuation) = AsyncStream.makeStream(of: HIDFactoryEvent.self)
  }

  func createDevice(_ configuration: HIDDeviceConfiguration) throws -> UInt32 {
    try lock.withLock {
      created += 1
      return try createResults.removeFirst().get()
    }
  }

  func terminateDevice(_ device: UInt32) {
    lock.withLock { terminated.append(device) }
  }

  func submitInputReport(_ bytes: [UInt8], to device: UInt32) {
    lock.withLock { inputs.append((device, bytes)) }
  }

  func createCount() -> Int { lock.withLock { created } }
  func terminatedDevices() -> [UInt32] { lock.withLock { terminated } }
  func submittedInputs() -> [(UInt32, [UInt8])] { lock.withLock { inputs } }
}

struct HIDFactoryPublisherTests {
  let description = VirtualHIDDeviceDescription(
    reportDescriptor: [0x05, 0x01],
    vendorID: 0x045E,
    productID: 0x02FD,
    versionNumber: 0x0408,
    manufacturer: "Microsoft",
    product: "Xbox Wireless Controller",
    serialNumber: "serial",
    transport: "Bluetooth",
    locationID: 0x1234,
    primaryUsagePage: 1,
    primaryUsage: 5
  )

  static let ignoredReports = VirtualHIDHostReports(
    setReport: { _, _, _ in kIOReturnSuccess },
    getReport: { _, _, _ in ([], kIOReturnSuccess) }
  )

  /// Sends a get-report request for `device` and returns the publisher's answer.
  static func answer(
    _ connection: FakeHIDFactoryConnection,
    device: UInt32
  ) async -> ([UInt8], IOReturn) {
    let (answers, answered) = AsyncStream.makeStream(of: ([UInt8], IOReturn).self)
    connection.continuation.yield(
      .getReport(
        HIDFactoryGetReport(device: device, type: .input, reportID: 0, capacity: 64) {
          answered.yield(($0, $1))
        }
      )
    )
    for await answer in answers { return answer }
    return ([], kIOReturnError)
  }

  /// Publishes `description` with ignored host reports and no loss handling.
  func publish(
    on publisher: DriverKitHIDFactoryPublisher
  ) async -> (any UserSpaceOutputDispatcher.VirtualDeviceBackend)? {
    await publisher.publish(description, hostReports: Self.ignoredReports) {}
  }

  @Test
  func configurationCarriesTheDescriptionAndAnswersEveryReportType() {
    let configuration = DriverKitHIDFactoryPublisher.configuration(for: description)
    #expect(configuration.reportDescriptor == description.reportDescriptor)
    #expect(configuration.transport == "Bluetooth")
    #expect(configuration.vendorID == 0x045E)
    #expect(configuration.productID == 0x02FD)
    #expect(configuration.versionNumber == 0x0408)
    #expect(configuration.locationID == 0x1234)
    #expect(configuration.serialNumber == "serial")
    #expect(configuration.answeredReportTypes == HIDGetReportTypes.all)
    #expect(configuration.acceptedHostReportTypes == HIDHostReportTypes.all)
  }

  @Test
  func busyCreateIsRetriedOnce() async {
    let connection = FakeHIDFactoryConnection(createResults: [
      .failure(HIDFactoryStatusError(status: kIOReturnBusy)), .success(7),
    ])
    let publisher = DriverKitHIDFactoryPublisher { connection }

    let backend = await publish(on: publisher)

    #expect(backend != nil)
    #expect(connection.createCount() == 2)
  }

  @Test(arguments: [
    [kIOReturnBusy, kIOReturnBusy], [kIOReturnNoSpace], [kIOReturnNotPermitted],
    [kIOReturnNotReady],
  ])
  func failedCreateFallsBack(_ statuses: [IOReturn]) async {
    let connection = FakeHIDFactoryConnection(
      createResults: statuses.map { .failure(HIDFactoryStatusError(status: $0)) }
    )
    let publisher = DriverKitHIDFactoryPublisher { connection }

    let backend = await publish(on: publisher)

    #expect(backend == nil)
    #expect(connection.createCount() == statuses.count)
  }

  @Test
  func failedConnectFallsBackAndTheNextPublishReconnects() async {
    let attempts = LockedAttempts()
    let connection = FakeHIDFactoryConnection(createResults: [.success(1)])
    let publisher = DriverKitHIDFactoryPublisher {
      if attempts.next() == 0 { throw HIDFactoryStatusError(status: kIOReturnNotFound) }
      return connection
    }

    #expect(await publish(on: publisher) == nil)
    #expect(await publish(on: publisher) != nil)
    #expect(attempts.count() == 2)
  }

  @Test
  func eventsReachTheDeviceHostReportsUntilTheSystemTerminatesIt() async throws {
    let connection = FakeHIDFactoryConnection(createResults: [.success(3)])
    let publisher = DriverKitHIDFactoryPublisher { connection }
    let (sets, setReceived) = AsyncStream.makeStream(of: [UInt8].self)
    let hostReports = VirtualHIDHostReports(
      setReport: { type, reportID, bytes in
        if type == .output, reportID == 3 { setReceived.yield(bytes) }
        return kIOReturnSuccess
      },
      getReport: { _, _, _ in ([0xAB], kIOReturnSuccess) }
    )
    let backend = try #require(
      await publisher.publish(description, hostReports: hostReports) {}
    )

    try await backend.send([1, 2])
    #expect(connection.submittedInputs().map(\.0) == [3])
    connection.continuation.yield(.setReport(device: 3, type: .output, reportID: 3, bytes: [3, 9]))
    var setIterator = sets.makeAsyncIterator()
    #expect(await setIterator.next() == [3, 9])
    let known = await Self.answer(connection, device: 3)
    #expect(known.0 == [0xAB])
    #expect(known.1 == kIOReturnSuccess)
    #expect(await Self.answer(connection, device: 99).1 == kIOReturnNotReady)

    connection.continuation.yield(.terminated(device: 3))
    #expect(await Self.answer(connection, device: 3).1 == kIOReturnNotReady)
  }

  @Test
  func closeTerminatesOnceAndWaitsForIt() async throws {
    let connection = FakeHIDFactoryConnection(createResults: [.success(5)])
    let publisher = DriverKitHIDFactoryPublisher { connection }
    let backend = try #require(
      await publish(on: publisher)
    )

    backend.close()
    backend.close()
    await backend.waitUntilClosed()

    #expect(connection.terminatedDevices() == [5])
    #expect(await Self.answer(connection, device: 5).1 == kIOReturnNotReady)
  }

  @Test
  func droppedConnectionRecreatesLiveDevicesAndResendsTheirLastReport() async throws {
    let first = FakeHIDFactoryConnection(createResults: [.success(1), .success(2)])
    let second = FakeHIDFactoryConnection(createResults: [.success(8)])
    let attempts = LockedAttempts()
    let publisher = DriverKitHIDFactoryPublisher { attempts.next() == 0 ? first : second }
    let losses = LockedAttempts()
    let kept = try #require(
      await publisher.publish(description, hostReports: Self.ignoredReports) { _ = losses.next() }
    )
    let closed = try #require(
      await publish(on: publisher)
    )
    try await kept.send([1, 2])
    closed.close()
    await closed.waitUntilClosed()

    first.continuation.finish()

    try #require(await eventually { second.submittedInputs().count == 1 })
    #expect(second.submittedInputs().first?.0 == 8)
    #expect(second.submittedInputs().first?.1 == [1, 2])
    #expect(second.createCount() == 1)
    try await kept.send([3])
    #expect(second.submittedInputs().map(\.0) == [8, 8])
    #expect(await Self.answer(second, device: 8).1 == kIOReturnSuccess)
    #expect(losses.count() == 0)
  }

  @Test
  func unreachableFactoryAfterADropFailsTheNextSend() async throws {
    let first = FakeHIDFactoryConnection(createResults: [.success(1)])
    let attempts = LockedAttempts()
    let publisher = DriverKitHIDFactoryPublisher(reconnectDelays: [0, 0]) {
      if attempts.next() == 0 { return first }
      throw HIDFactoryStatusError(status: kIOReturnNotFound)
    }
    let losses = LockedAttempts()
    let backend = try #require(
      await publisher.publish(description, hostReports: Self.ignoredReports) { _ = losses.next() }
    )

    first.continuation.finish()

    #expect(await eventually { attempts.count() == 3 })
    #expect(await eventually { (try? await backend.send([1])) == nil })
    #expect(losses.count() == 1)
  }
}

final class LockedAttempts: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      defer { value += 1 }
      return value
    }
  }

  func count() -> Int { lock.withLock { value } }
}

/// Polls `condition` for up to two seconds.
func eventually(_ condition: () async -> Bool) async -> Bool {
  for _ in 0..<200 {
    if await condition() { return true }
    try? await Task.sleep(nanoseconds: 10_000_000)
  }
  return await condition()
}
