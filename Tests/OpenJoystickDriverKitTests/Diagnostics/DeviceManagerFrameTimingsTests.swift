import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

private final class PublishedFrameDispatcher: OutputDispatcher, @unchecked Sendable {
  var suppressOutput = false

  func dispatch(
    _: ControllerEvent,
    from _: LogicalControllerID
  ) {}

  func activateOutput(for _: LogicalControllerID) {}

  func dispatchPublishing(
    _: ControllerEvent,
    from _: LogicalControllerID,
    onPublished: @Sendable () -> Void
  ) {
    onPublished()
  }
}

struct DeviceManagerFrameTimingsTests {
  /// A real HID report through the detection loop, the pipeline, and the manager's query surface:
  /// the snapshot the `getFrameTimings` request answers lists every stage, endpoint delivery last.
  @Test
  func aHIDReportAndItsEndpointDeliveryAppearInTheSnapshot() async throws {
    let backend = ScriptedHIDAccessBackend()
    await backend.enableOutputReports()
    await backend.enableFeatureReports()
    let manager = DeviceManager(
      dispatcher: PublishedFrameDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend)
    )
    await manager.markStartedForTest()
    let connection = StickDeliveryLatencyTests.gamepadConnection()
    await backend.setConnectionSnapshots([
      HIDDeviceConnectionSnapshot(connection: connection, ownership: .exclusive)
    ])
    await manager.ensureHIDDetectionState(for: .granted)
    await backend.waitForAttempt(1)
    await backend.yield(.connected(connection: connection, ownership: .exclusive), attempt: 1)
    await waitUntil("manager.pipelines is not empty") { await !manager.pipelines.isEmpty }
    try #require(await !manager.pipelines.isEmpty)

    await backend.yield(
      StickDeliveryLatencyTests.gamepadReport(leftX: 0xA0, connection: connection),
      attempt: 1
    )
    var snapshot = await manager.frameTimingsSnapshot(lastSeconds: nil, now: 0)
    let delivered: (ApplicationServiceFrameTimingsPayload) -> Bool = {
      $0.controllers.first?.frames.last?.stages.contains { $0.stage == .deliveryVirtualDevice }
        == true
    }
    await waitUntil("virtual-device delivery stage recorded") {
      snapshot = await manager.frameTimingsSnapshot(lastSeconds: nil, now: 0)
      return delivered(snapshot)
    }
    let controller = try #require(snapshot.controllers.first)
    let token = try #require(ControllerSessionToken(rawValue: controller.controller))
    await manager.endpointDelivered(session: token, at: UInt64.max)
    let stages = await manager.frameTimingsSnapshot(lastSeconds: nil, now: 0).controllers.first?
      .frames.last?.stages
    await manager.stop()

    #expect(
      stages?.map(\.stage) == [
        .read, .parse, .dispatch, .deliveryVirtualDevice, .deliveryEndpoint,
      ],
      "\(String(describing: stages))"
    )
    #expect(stages?.last?.nanoseconds == UInt64.max)
  }
}
