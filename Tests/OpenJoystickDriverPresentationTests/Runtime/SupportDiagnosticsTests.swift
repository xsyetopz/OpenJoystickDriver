import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

@Suite(.serialized)
struct SupportDiagnosticsTests {
  // The report reads the platform host, which the executable installs at launch.
  init() { PlatformHosts.install(FakePlatformHost()) }

  @Test
  func summarizesControllerOutputWithoutHIDDetails() async {
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready"),
      hidGamepads: [
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 0x1234,
          productID: 0x5678,
          product: "OpenJoystickDriver Virtual Controller",
          transport: "Virtual",
          locationID: 42,
          serialKind: .ojdUserSpace,
          ioUserClass: "IOHIDUserDevice",
          isOJDUserSpace: true
        ),
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 0x4321,
          productID: 0x8765,
          product: "Other controller",
          transport: "USB",
          locationID: 99,
          serialKind: .present,
          ioUserClass: "IOHIDDevice",
          isOJDUserSpace: false
        ),
      ]
    )
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsPayloads: [diagnostics])
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }

    await supportReport.loadSupportDiagnostics()

    let state = await MainActor.run { supportReport.supportDiagnosticsState }
    guard case .available(let details) = state else {
      Issue.record("Expected support diagnostics to be available")
      return
    }
    #expect(details.virtualControllerOutputState == .available)
    #expect(details.virtualControllerCount == 1)
  }

  @Test
  func newerRetryWinsOverAnOlderResponse() async {
    let gateway = SupportDiagnosticsGatewayStub(
      diagnosticsPayloads: [
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: false,
          userSpaceVirtualDeviceStatus: .off,
          hidGamepads: [],
        ),
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready"),
          hidGamepads: []
        ),
      ],
      diagnosticsDelayNanoseconds: [100_000_000, 0]
    )
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }
    let first = Task { @MainActor in await supportReport.loadSupportDiagnostics() }
    await waitUntil("the first diagnostics read starts") { await gateway.diagnosticsReadCount >= 1 }

    await supportReport.loadSupportDiagnostics()
    await first.value

    let state = await MainActor.run { supportReport.supportDiagnosticsState }
    guard case .available(let details) = state else {
      Issue.record("Expected the newer diagnostics response to remain authoritative")
      return
    }
    #expect(details.virtualControllerOutputState == .available)
  }

  @Test
  func unavailableDiagnosticsRemainScopedToSupport() async {
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsShouldFail: true)
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }

    await supportReport.loadSupportDiagnostics()

    let state = await MainActor.run { supportReport.supportDiagnosticsState }
    guard case .unavailable = state else {
      Issue.record("Expected unavailable support diagnostics")
      return
    }
  }

  @Test
  func savesRedactedReportFromGatewaySnapshots() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: "private-serial",
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("device-report")
    )
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready"),
      hidGamepads: [
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 0x1234,
          productID: 0x5678,
          product: "Virtual Controller",
          transport: "Virtual",
          locationID: 42,
          serialKind: .ojdUserSpace,
          ioUserClass: "IOHIDUserDevice",
          isOJDUserSpace: true
        )
      ]
    )
    let gateway = SupportDiagnosticsGatewayStub(
      statusPayload: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready")
      ),
      diagnosticsPayloads: [diagnostics]
    )
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriver-support-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }

    await supportReport.saveSupportReport(to: outputURL)

    let reportSaved = await MainActor.run {
      if case .saved = supportReport.supportReportState { return true }
      return false
    }
    guard reportSaved else {
      Issue.record("Expected the support report to be saved")
      return
    }
    let report = try JSONDecoder().decode(SupportReport.self, from: Data(contentsOf: outputURL))
    #expect(report.data.controllers.count == 1)
    guard let controller = report.data.controllers.first else {
      Issue.record("Expected the report to contain the connected controller")
      return
    }
    #expect(controller.serialNumberPresent)
    #expect(report.data.privacy.includesRawSerialNumbers == false)
    #expect(report.data.privacy.includesFilesystemPaths == false)
    #expect(report.data.privacy.includesHIDLocationIDs == false)
    #expect(report.data.hidGamepads.count == 1)
  }

  @Test
  func reportCarriesTheFrameTimingsOfTheService() async throws {
    let timings = ControllerFrameTimings.fixture

    let report = try await savedReport(SupportDiagnosticsGatewayStub(frameTimings: [timings]))

    #expect(report.data.frameTimings == [timings])
  }

  @Test
  func reportHasNoFrameTimingsWhenTheServiceIsUnreachable() async throws {
    let report = try await savedReport(SupportDiagnosticsGatewayStub(frameTimings: nil))

    #expect(report.data.frameTimings.isEmpty)
  }

  private func savedReport(_ gateway: SupportDiagnosticsGatewayStub) async throws -> SupportReport {
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriver-support-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }
    await supportReport.saveSupportReport(to: outputURL)
    return try JSONDecoder().decode(SupportReport.self, from: Data(contentsOf: outputURL))
  }

  @Test
  func collectingDiagnosticsDoesNotLeaveReportSaving() async {
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsDelayNanoseconds: [100_000_000, 0])
    let supportReport = await MainActor.run { SupportReportModel(gateway: gateway) }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriver-support-race-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let report = Task { @MainActor in await supportReport.saveSupportReport(to: outputURL) }
    await waitUntil("the first diagnostics read starts") { await gateway.diagnosticsReadCount >= 1 }
    await supportReport.loadSupportDiagnostics()
    await report.value

    let reportState = await MainActor.run { supportReport.supportReportState }
    guard case .saved = reportState else {
      Issue.record("Expected a diagnostics refresh to leave report export in a terminal state")
      return
    }
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
  }
}

private actor SupportDiagnosticsGatewayStub: ApplicationServiceGateway {
  let statusPayload: ApplicationServiceStatusPayload
  let diagnosticsPayloads: [ApplicationServiceVirtualDeviceDiagnosticsPayload]
  let diagnosticsDelayNanoseconds: [UInt64]
  let diagnosticsShouldFail: Bool
  let frameTimingsPayload: [ControllerFrameTimings]?
  var diagnosticsReadCount = 0

  init(
    statusPayload: ApplicationServiceStatusPayload = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .backend("ready")
    ),
    diagnosticsPayloads: [ApplicationServiceVirtualDeviceDiagnosticsPayload] = [
      ApplicationServiceVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: .backend("ready"),
        hidGamepads: []
      )
    ],
    diagnosticsDelayNanoseconds: [UInt64] = [],
    diagnosticsShouldFail: Bool = false,
    frameTimings: [ControllerFrameTimings]? = []
  ) {
    self.frameTimingsPayload = frameTimings
    self.statusPayload = statusPayload
    self.diagnosticsPayloads =
      diagnosticsPayloads.isEmpty
      ? [
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: .backend("ready"),
          hidGamepads: []
        )
      ] : diagnosticsPayloads
    self.diagnosticsDelayNanoseconds = diagnosticsDelayNanoseconds
    self.diagnosticsShouldFail = diagnosticsShouldFail
  }

  func status() -> ApplicationServiceStatusPayload { statusPayload }

  func frameTimings(lastSeconds _: Int?) throws -> ApplicationServiceFrameTimingsPayload {
    guard let frameTimingsPayload else { throw ApplicationServiceClientError.timeout }
    return ApplicationServiceFrameTimingsPayload(controllers: frameTimingsPayload)
  }

  func virtualDeviceDiagnostics() async throws -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    if diagnosticsShouldFail { throw ApplicationServiceClientError.timeout }
    let index = min(diagnosticsReadCount, diagnosticsPayloads.count - 1)
    let delay =
      diagnosticsDelayNanoseconds.indices.contains(diagnosticsReadCount)
      ? diagnosticsDelayNanoseconds[diagnosticsReadCount] : 0
    diagnosticsReadCount += 1
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    return diagnosticsPayloads[index]
  }

  func requestPermissions() -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(inputRead: .granted, inputInject: .granted)
  }

  func requestPermission(
    _: PermissionManager.Requirement
  ) -> PermissionManager.Snapshot { requestPermissions() }

  func controllerState(for _: ControllerReference) -> ControllerState? { nil }

  func virtualOutputState(
    for _: ControllerReference
  ) -> ApplicationServiceVirtualOutputState? { nil }

  func packetLog(for _: ControllerReference) -> [PacketLogEntry] { [] }

  func remappingSnapshot() -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }

  func remappingProfile(id _: UUID) throws -> RemappingProfile {
    throw ApplicationServiceClientError.invalidResponse
  }

  func createRemappingProfile(
    _: RemappingProfile
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func updateRemappingProfile(
    _: RemappingProfile,
    expectedCurrent _: RemappingProfile
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func importRemappingProfile(
    _: RemappingProfile
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func deleteRemappingProfile(id _: UUID) -> ApplicationServiceRemappingSnapshotPayload {
    remappingSnapshot()
  }

  func activateRemappingProfile(
    id _: UUID,
    allowEmpty _: Bool
  ) -> ApplicationServiceRemappingSnapshotPayload {
    remappingSnapshot()
  }

  func deactivateRemappingProfile(
    vendorID _: UInt16,
    productID _: UInt16
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func deactivateRemappingProfile(
    profileID _: UUID
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func remappingPostEventAccess() -> RemappingPostEventAccessState { .granted }

  func requestRemappingPostEventAccess() -> RemappingPostEventAccessState { .granted }

  func pairRemappingJoyCons(
    left _: ControllerReference,
    right _: ControllerReference,
    profileID _: UUID
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func unpairRemappingJoyCons(
    sessionID _: UUID
  ) -> ApplicationServiceRemappingSnapshotPayload { remappingSnapshot() }

  func setVirtualHIDProfileOverride(
    _ profile: VirtualHIDProfileID,
    for _: ControllerReference,
    scope _: VirtualHIDProfileOverrideScope
  ) -> VirtualHIDProfileOverrideResult {
    VirtualHIDProfileOverrideResult(
      requested: profile,
      live: profile,
      source: .override,
      failure: nil
    )
  }

  func resetVirtualHIDProfileOverride(
    for _: ControllerReference,
    scope _: VirtualHIDProfileOverrideScope
  ) -> VirtualHIDProfileOverrideResult {
    VirtualHIDProfileOverrideResult(
      requested: nil,
      live: .generic,
      source: .automatic,
      failure: nil
    )
  }

  func resetAllVirtualHIDProfileOverrides() -> Bool { true }

  func setControllerTuning(
    model _: ControllerModelID,
    key _: ControllerTuning.Key,
    value _: Double?
  ) throws -> ControllerTuningResult {
    throw ApplicationServiceClientError.invalidResponse
  }
}

extension SupportDiagnosticsGatewayStub {
  func setControllerServer(
    model _: ControllerModelID,
    server _: ControllerServer
  ) throws -> ControllerServerResult {
    throw ApplicationServiceClientError.invalidResponse
  }

  func suspendController(_: ControllerReference) throws -> ControllerSuspendResult {
    throw ApplicationServiceClientError.invalidResponse
  }

  func resumeController(_: ControllerReference) throws -> ControllerResumeResult {
    throw ApplicationServiceClientError.invalidResponse
  }

  func disconnectWirelessController(
    _: ControllerReference
  ) throws -> WirelessControllerDisconnectResult {
    throw ApplicationServiceClientError.invalidResponse
  }

  func deleteDamagedRemappingProfile(
    issueID _: UUID
  ) throws -> ApplicationServiceRemappingSnapshotPayload {
    throw ApplicationServiceClientError.invalidResponse
  }

  func resetRemappingProfileLibrary(
    issueID _: UUID
  ) throws -> ApplicationServiceRemappingSnapshotPayload {
    throw ApplicationServiceClientError.invalidResponse
  }
}
