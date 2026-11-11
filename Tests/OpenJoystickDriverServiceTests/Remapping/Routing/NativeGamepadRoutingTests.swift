import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit
@testable import OpenJoystickDriverService

private final class NativePublicationProbe: VirtualOutputDispatching,
  VirtualOutputControllerActivating, @unchecked Sendable
{
  private let lock = NSLock()
  private var activationCount = 0
  private var dispatchCount = 0
  var suppressOutput = false
  var status: VirtualOutputBackendStatus { .backend("probe") }
  var lastRumbleStatus: String? { nil }
  var publications: Int { lock.withLock { activationCount + dispatchCount } }

  func activate(for identifiers: [LogicalControllerID]) {
    lock.withLock { activationCount += identifiers.count }
  }
  func activate(controller _: LogicalControllerID) { lock.withLock { activationCount += 1 } }
  func dispatch(_: ControllerEvent, from _: LogicalControllerID) {
    lock.withLock { dispatchCount += 1 }
  }
  func activateOutput(for _: LogicalControllerID) { lock.withLock { dispatchCount += 1 } }
  func close() {}
}

/// A natively supported pad is observed: its input reaches remapping, and no virtual gamepad is
/// published for it.
@Suite(.serialized)
struct NativeGamepadRoutingTests {
  @Test
  func automaticIdentityNeverPublishesForANativePad() async throws {
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey
    )
    let identifier = try await Self.connect(native: true, to: manager, locationID: 181)
    let probe = NativePublicationProbe()
    let automatic = AutomaticUserSpaceOutputDispatcher(
      deviceManager: manager,
      builder: { _ in probe },
      descriptionsProvider: {
        await manager.connectedDeviceDescriptions().reduce(into: [:]) {
          $0[$1.logicalControllerID] = ApplicationServiceDeviceDescription(snapshot: $1)
        }
      }
    )

    try await automatic.activate(controller: identifier)
    await automatic.dispatch(changes: [.press(.south)], from: identifier)

    #expect(probe.publications == 0)
    await automatic.close()
    await manager.stop()
  }

  @Test
  func remappingProfileRunsOnANativePadsInput() async throws {
    let profile = Self.profile(policy: .systemInput)
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let manager = DeviceManager(
      dispatcher: harness.router,
      installationKey: testPortKeyInstallationKey
    )
    _ = try await Self.connect(native: true, to: manager, locationID: 182)

    await Self.pressCross(on: manager, locationID: 182)

    #expect(harness.recorder.snapshot().contains { if case .system = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  @Test
  func noProfileMeansNoDispatchUntilAProfileIsSelected() async throws {
    let harness = try await RemappingRouterHarness.make()
    defer { harness.removeFiles() }
    let manager = DeviceManager(
      dispatcher: harness.router,
      installationKey: testPortKeyInstallationKey
    )
    let identifier = try await Self.connect(native: true, to: manager, locationID: 184)
    #expect(!harness.router.wantsObservedInput(from: identifier))

    let profile = Self.profile(policy: .systemInput)
    try await harness.library.create(profile)
    try await harness.library.activate(profileID: profile.id)
    try await harness.router.refresh(identifier)
    #expect(harness.router.wantsObservedInput(from: identifier))

    await Self.pressCross(on: manager, locationID: 184)
    #expect(harness.recorder.snapshot().contains { if case .system = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  @Test
  func theRouterWantsPointerInputOnlyWhileTheActiveProfileBindsThePointer() async throws {
    let plain = Self.profile(policy: .systemInput)
    let harness = try await RemappingRouterHarness.make(profile: plain)
    defer { harness.removeFiles() }
    let manager = DeviceManager(
      dispatcher: harness.router,
      installationKey: testPortKeyInstallationKey
    )
    let identifier = try await Self.connect(native: true, to: manager, locationID: 185)
    #expect(!harness.router.wantsPointerInput(from: identifier))

    let aiming = RemappingProfile(
      name: "Aiming",
      device: plain.device,
      applicationScope: plain.applicationScope,
      outputPolicy: .systemInput,
      bindings: [
        RemappingBinding(
          source: .axis(.pointerX),
          destination: .mouseMovement(.x),
          axisTuning: RemappingAxisTuning(deadzone: 0, gain: 1)
        )
      ]
    )
    try await harness.library.create(aiming)
    try await harness.library.activate(profileID: aiming.id)
    try await harness.router.refresh(identifier)
    #expect(harness.router.wantsPointerInput(from: identifier))

    try await harness.library.activate(profileID: plain.id)
    try await harness.router.refresh(identifier)
    #expect(!harness.router.wantsPointerInput(from: identifier))
    await manager.stop()
    try await harness.router.shutdown()
  }

  @Test
  func virtualGamepadRemappingIsRejectedForANativePad() async throws {
    let profile = Self.profile(policy: RemappingOutputPolicy(virtualGamepad: .mapped))
    let harness = try await RemappingRouterHarness.make(profile: profile)
    defer { harness.removeFiles() }
    let manager = DeviceManager(
      dispatcher: harness.router,
      installationKey: testPortKeyInstallationKey
    )
    let identifier = try await Self.connect(native: true, to: manager, locationID: 183)

    await Self.pressCross(on: manager, locationID: 183)

    #expect(await harness.router.status(for: identifier)?.eligibility == .physicalInputNotExclusive)
    #expect(!harness.recorder.snapshot().contains { if case .gamepad = $0 { true } else { false } })
    await manager.stop()
    try await harness.router.shutdown()
  }

  private static func connect(
    native: Bool,
    to manager: DeviceManager,
    locationID: UInt32
  ) async throws -> LogicalControllerID {
    let connection = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x054C,
        productID: 0x09CC,
        productName: "Wireless Controller",
        transportProperty: "USB",
        physicalLocationIdentifier: locationID,
        interfaces: [
          PhysicalInterfaceSignature(
            hostTransport: .usb,
            accessBackend: .hid,
            hidLayout: HIDLayoutSummary(reportDescriptor: Data(GamepadHIDDescriptor.descriptor))
          )
        ],
        nativePassThrough: native
      ),
      routingAddress: .ioKit(locationID: locationID, interfaceNumber: nil)
    )
    await manager.handleHIDEvent(
      .connected(connection: connection, ownership: native ? .unknown : .exclusive)
    )
    return try #require(await manager.pipelines.keys.first { $0.address?.locationID == locationID })
  }

  private static func profile(policy: RemappingOutputPolicy) -> RemappingProfile {
    RemappingProfile(
      name: "Native",
      device: RemappingDeviceScope(vendorID: 0x054C, productID: 0x09CC),
      applicationScope: .application(appIDs: ["com.example.Game"]),
      outputPolicy: policy,
      bindings: [
        RemappingBinding(
          source: .button(.south),
          destination: .keyboard(key: .space, modifiers: [])
        )
      ]
    )
  }

  /// Sends a neutral USB DualShock 4 report, so a slow run that trips input liveness recovers,
  /// then one with Cross held.
  private static func pressCross(on manager: DeviceManager, locationID: UInt32) async {
    for (face, timestamp) in [(UInt8(0x08), UInt8(1)), (0x28, 2)] {
      var report = [UInt8](repeating: 0, count: 64)
      report.replaceSubrange(0..<6, with: [0x01, 0x80, 0x80, 0x80, 0x80, face])
      report[10] = timestamp
      await manager.handleHIDEvent(
        .inputReport(
          address: .ioKit(locationID: locationID, interfaceNumber: nil),
          connectionID: UUID(),
          reportID: 0x01,
          data: Data(report)
        )
      )
    }
  }
}
