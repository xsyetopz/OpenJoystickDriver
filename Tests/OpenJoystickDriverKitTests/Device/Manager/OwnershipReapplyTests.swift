import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

/// A changed `ownership` reaches a connected controller without a replug.
///
/// The GameSir connections are synthetic, as in `HIDLocationRoutingTests`.
@Suite(.timeLimit(.minutes(2)))
struct OwnershipReapplyTests {
  private static let changedModel = ControllerModelID(vendorID: 0x3537, productID: 0x100B)

  /// A record reload lets the HID backend admit a changed model again with its changed native flag,
  /// and `readmitHIDConnections` does not admit it a second time.
  ///
  /// Other models keep their sessions.
  @Test
  func recordReloadReadmitsTheChangedModelOnceWithItsNewNativeFlag() async throws {
    let scripted = ScriptedHIDAccessBackend()
    await scripted.enableOutputReports()
    await scripted.enableFeatureReports()
    let backend = OwnershipReapplyBackend(scripted)
    let manager = DeviceManager(
      dispatcher: HIDRoleEventRecorder(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await backend.attach(manager)
    await manager.markStartedForTest()
    let native = Self.gameSir(productID: 0x100B, locationID: 0x0021_0000, native: true)
    let other = Self.gameSir(productID: 0x1053, locationID: 0x0022_0000, native: false)
    let seized = Self.gameSir(productID: 0x100B, locationID: 0x0021_0000, native: false)
    await backend.setSnapshots([native, other])
    await backend.replace(native, with: seized)
    await manager.handleHIDEvent(.connected(connection: native, ownership: .unknown))
    await manager.handleHIDEvent(.connected(connection: other, ownership: .exclusive))
    let changedID = LogicalControllerID(
      vendorID: 0x3537,
      productID: 0x100B,
      locationID: 0x0021_0000
    )
    let otherID = LogicalControllerID(vendorID: 0x3537, productID: 0x1053, locationID: 0x0022_0000)
    let otherPipeline = try #require(await manager.pipelines[otherID])

    await manager.reloadControllerRecords(changing: [Self.changedModel])
    await Self.waitForHIDInitializations(of: manager)

    #expect(await backend.reevaluated() == [[Self.changedModel]])
    #expect(Set(await manager.pipelines.keys) == [changedID, otherID])
    #expect(await manager.deviceInfos[changedID]?.hidConnectionID == seized.connectionID)
    #expect(await manager.deviceInfos[changedID]?.physicalDevice?.nativePassThrough == false)
    let readmitted = try #require(await backend.admittedPipelines()[changedID])
    #expect(await readmitted.observedInputDemand == nil)
    // A second admission by `readmitHIDConnections` would replace the backend's pipeline.
    #expect(await manager.pipelines[changedID] === readmitted)
    #expect(await manager.pipelines[otherID] === otherPipeline)
    await manager.stop()
  }

  /// A model that GameController supports, set to `ownership: ojd`, is seized, so its pipeline has
  /// no observed-input gate and dispatches each changed report even with no remapping route.
  @Test
  func anOJDOwnedNativeModelDispatchesEachChangedReportWithoutARoute() async throws {
    let records = try Self.recordsOwningTheChangedModel()
    let catalog = DeviceCatalog(records: records)
    #expect(catalog.takesOwnership(of: Self.changedModel))
    // `HIDDeviceStream.nativePassThrough` for a model that GameController supports.
    let nativePassThrough =
      !catalog.takesOwnership(of: Self.changedModel)
    let owned = try await Self.dispatchedReports(nativePassThrough: nativePassThrough)
    #expect(owned.observedGate == false)
    #expect(owned.dispatched == 2)
    // The same controller left to macOS is gated, so the test depends on the flag.
    let native = try await Self.dispatchedReports(nativePassThrough: true)
    #expect(native.observedGate)
    #expect(native.dispatched == 0)
  }

  /// Sends a pressed report and then a neutral one through a GameSir with `nativePassThrough`, to
  /// a dispatcher whose remapping wants no observed input, the passthrough profile.
  private static func dispatchedReports(
    nativePassThrough: Bool
  ) async throws -> (observedGate: Bool, dispatched: Int) {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let dispatcher = UnroutedDispatcher()
    let manager = DeviceManager(
      dispatcher: dispatcher,
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let locationID: UInt32 = 0x0021_0000
    let connection = gameSir(
      productID: 0x100B,
      locationID: locationID,
      native: nativePassThrough
    )
    let ownership: HIDInputOwnership = nativePassThrough ? .unknown : .exclusive
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: ownership)
    ])
    await manager.handleHIDEvent(.connected(connection: connection, ownership: ownership))
    let pipeline = try #require(await manager.pipelines.values.first)
    let neutral = Data([0x12, 0x80, 0x80, 0x80, 0x80] + [UInt8](repeating: 0, count: 59))
    let before = dispatcher.count
    for report in [HIDLocationRoutingTests.aPressed, neutral] {
      await manager.handleHIDEvent(
        .inputReport(
          address: .ioKit(locationID: locationID, interfaceNumber: nil),
          connectionID: connection.connectionID,
          reportID: 0x12,
          data: report
        )
      )
    }
    let result = (await pipeline.observedInputDemand != nil, dispatcher.count - before)
    await manager.stop()
    return result
  }

  /// The bundled records with a user `patch` that sets `ownership: ojd` for the changed model.
  private static func recordsOwningTheChangedModel() throws -> ControllerRecordSet {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-ownership-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try PropertyListFixture.data(
      tree: ControllerPatch.document(
        selector: .identity(ControllerModelID(vendorID: 0x3537, productID: 0x100B)),
        body: ["server": "OJD"]
      )
    )
    .write(to: directory.appendingPathComponent("3537-100b.patch.plist"))
    let records = ControllerRecordSet.load(userDirectory: directory)
    #expect(records.problems.isEmpty)
    return records
  }

  private static func waitForHIDInitializations(of manager: DeviceManager) async {
    await waitUntil("manager.hidInitializationTasks.isEmpty") {
      await manager.hidInitializationTasks.isEmpty
    }
  }

  private final class Posts: @unchecked Sendable {
    private let lock = NSLock()
    private var posts = 0
    var count: Int { lock.withLock { posts } }
    func increment() { lock.withLock { posts += 1 } }
  }

  /// A changed HID ownership announces a status change from the manager once, and an unchanged
  /// one announces nothing.
  @Test
  func aChangedHIDOwnershipAnnouncesOnceAndTheSameOwnershipAnnouncesNothing() async throws {
    let backend = ScriptedHIDAccessBackend()
    let manager = DeviceManager(
      dispatcher: HIDRoleEventRecorder(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let locationID: UInt32 = 0x0021_0000
    let connection = Self.gameSir(productID: 0x100B, locationID: locationID, native: false)
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await manager.handleHIDEvent(.connected(connection: connection, ownership: .exclusive))
    let posts = Posts()
    let observer = NotificationCenter.default.addObserver(
      forName: .ojdServiceStatusDidChange,
      object: manager,
      queue: nil
    ) { _ in posts.increment() }
    defer { NotificationCenter.default.removeObserver(observer) }
    let address = ControllerConnectionAddress.ioKit(locationID: locationID, interfaceNumber: nil)

    await manager.handleHIDEvent(.ownershipChanged(address: address, ownership: .shared))
    #expect(posts.count == 1)
    await manager.handleHIDEvent(.ownershipChanged(address: address, ownership: .shared))
    #expect(posts.count == 1)
    await manager.stop()
  }

  private static func gameSir(
    productID: UInt16,
    locationID: UInt32,
    native: Bool,
    interface: UInt8 = 0
  ) -> HIDDeviceConnection {
    HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x3537,
        productID: productID,
        productName: "GameSir",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: interface,
            hostTransport: .usb,
            accessBackend: .hid,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ],
        nativePassThrough: native
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
  }
}

/// Counts dispatched events and, like a remapping router with no route for any controller, wants
/// no observed input.
private final class UnroutedDispatcher: OutputDispatcher, ObservedInputDemand,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var dispatched = 0
  private var suppressed = false

  var suppressOutput: Bool {
    get { lock.withLock { suppressed } }
    set { lock.withLock { suppressed = newValue } }
  }

  var count: Int { lock.withLock { dispatched } }

  func dispatch(
    _: ControllerEvent,
    from _: LogicalControllerID
  ) { lock.withLock { dispatched += 1 } }

  func activateOutput(for _: LogicalControllerID) {}

  func wantsObservedInput(from _: LogicalControllerID) -> Bool { false }
}

/// Forwards to the scripted fake and, like `HIDDeviceStream`, admits a changed model again by
/// sending its disconnect and its replacement connection to the manager.
private actor OwnershipReapplyBackend: HIDAccessBackend {
  private let scripted: ScriptedHIDAccessBackend
  private weak var manager: DeviceManager?
  private var snapshots: [HIDDeviceConnection] = []
  private var replacements: [UUID: HIDDeviceConnection] = [:]
  private var calls: [Set<ControllerModelID>] = []
  private var admitted: [LogicalControllerID: DevicePipeline] = [:]

  init(_ scripted: ScriptedHIDAccessBackend) { self.scripted = scripted }

  func attach(_ manager: DeviceManager) { self.manager = manager }

  func setSnapshots(_ connections: [HIDDeviceConnection]) async {
    snapshots = connections
    await scripted.setConnectionSnapshots(
      connections.map { HIDDeviceConnectionSnapshot(connection: $0, ownership: .exclusive) }
    )
  }

  func replace(_ connection: HIDDeviceConnection, with replacement: HIDDeviceConnection) {
    replacements[connection.connectionID] = replacement
  }

  func reevaluated() -> [Set<ControllerModelID>] { calls }

  /// The manager's pipelines once the admissions this backend sent have finished.
  func admittedPipelines() -> [LogicalControllerID: DevicePipeline] { admitted }

  func reevaluateOwnership(of models: Set<ControllerModelID>) async -> Set<UUID> {
    calls.append(models)
    let cycled = snapshots.filter { replacements[$0.connectionID] != nil }
    for old in cycled { await manager?.handleHIDEvent(.disconnected(connection: old)) }
    var admittedIDs: Set<UUID> = []
    for old in cycled {
      guard let new = replacements.removeValue(forKey: old.connectionID) else { continue }
      await setSnapshots(snapshots.map { $0.connectionID == old.connectionID ? new : $0 })
      await manager?.handleHIDEvent(.connected(connection: new, ownership: .exclusive))
      admittedIDs.insert(new.connectionID)
    }
    if let manager {
      await waitUntil("manager.hidInitializationTasks.isEmpty") {
        await manager.hidInitializationTasks.isEmpty
      }
      admitted = await manager.pipelines
    }
    return admittedIDs
  }

  func deviceEvents() async -> AsyncStream<HIDDeviceEvent> { await scripted.deviceEvents() }

  func currentConnectionSnapshots() async -> [HIDDeviceConnectionSnapshot]? {
    await scripted.currentConnectionSnapshots()
  }

  func setOutputReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setOutputReport(address: address, report: report)
  }

  func setOutputReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setOutputReport(connection: connection, report: report)
  }

  func setFeatureReport(
    address: ControllerConnectionAddress,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setFeatureReport(address: address, report: report)
  }

  func setFeatureReport(
    connection: HIDDeviceConnection,
    report: PhysicalHIDOutputReport
  ) async -> PhysicalHIDReportResult<Void> {
    await scripted.setFeatureReport(connection: connection, report: report)
  }

  func getFeatureReport(
    address: ControllerConnectionAddress,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await scripted.getFeatureReport(address: address, request: request)
  }

  func getFeatureReport(
    connection: HIDDeviceConnection,
    request: PhysicalHIDFeatureReadRequest
  ) async -> PhysicalHIDReportResult<Data> {
    await scripted.getFeatureReport(connection: connection, request: request)
  }

  func releaseInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    await scripted.releaseInputClaim(address: address)
  }

  func reacquireInputClaim(address: ControllerConnectionAddress) async -> PhysicalHIDClaimResult {
    await scripted.reacquireInputClaim(address: address)
  }

  func retryInputClaim(address: ControllerConnectionAddress) async {
    await scripted.retryInputClaim(address: address)
  }

  func routeElementValues(connection: HIDDeviceConnection) async {
    await scripted.routeElementValues(connection: connection)
  }
}
