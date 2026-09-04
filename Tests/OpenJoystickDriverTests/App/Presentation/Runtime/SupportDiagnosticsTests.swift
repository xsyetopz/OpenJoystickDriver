import Foundation
import OpenJoystickDriverKit
import Testing

@testable import OpenJoystickDriver

@Suite(.serialized) struct SupportDiagnosticsTests {
  @Test func summarizesControllerOutputWithoutHIDDetails() async {
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
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
        )
      ]
    )
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsPayloads: [diagnostics])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.loadSupportDiagnostics()

    let state = await MainActor.run { viewModel.supportDiagnosticsState }
    guard case .available(let details) = state else {
      Issue.record("Expected support diagnostics to be available")
      return
    }
    #expect(details.virtualControllerOutputState == .available)
    #expect(details.virtualControllerCount == 1)
  }

  @Test func newerRetryWinsOverAnOlderResponse() async {
    let gateway = SupportDiagnosticsGatewayStub(
      diagnosticsPayloads: [
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: false,
          userSpaceVirtualDeviceStatus: "off",
          hidGamepads: [],
        ),
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: "ready",
          hidGamepads: []
        )
      ],
      diagnosticsDelayNanoseconds: [100_000_000, 0]
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let first = Task { @MainActor in await viewModel.loadSupportDiagnostics() }
    try? await Task.sleep(nanoseconds: 10_000_000)

    await viewModel.loadSupportDiagnostics()
    await first.value

    let state = await MainActor.run { viewModel.supportDiagnosticsState }
    guard case .available(let details) = state else {
      Issue.record("Expected the newer diagnostics response to remain authoritative")
      return
    }
    #expect(details.virtualControllerOutputState == .available)
  }

  @Test func unavailableDiagnosticsRemainScopedToSupport() async {
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsShouldFail: true)
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }

    await viewModel.loadSupportDiagnostics()

    let state = await MainActor.run { viewModel.supportDiagnosticsState }
    guard case .unavailable = state else {
      Issue.record("Expected unavailable support diagnostics")
      return
    }
    #expect(await MainActor.run { viewModel.lastError } == nil)
  }

  @Test func savesRedactedReportFromGatewaySnapshots() async throws {
    let device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      parser: "GIP",
      connection: "USB",
      serialNumber: "private-serial",
      runtimeIdentifier: "session-device-report"
    )
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
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
        inputMonitoring: "granted",
        accessibility: "granted",
        connectedDevices: [device],
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
      ),
      diagnosticsPayloads: [diagnostics]
    )
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriver-support-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }

    await viewModel.saveSupportReport(to: outputURL)

    let reportSaved = await MainActor.run {
      if case .saved = viewModel.supportReportState { return true }
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

  @Test func collectingDiagnosticsDoesNotLeaveReportSaving() async throws {
    let gateway = SupportDiagnosticsGatewayStub(diagnosticsDelayNanoseconds: [100_000_000, 0])
    let viewModel = await MainActor.run { RuntimeViewModel(gateway: gateway) }
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "OpenJoystickDriver-support-race-\(UUID().uuidString).json"
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let report = Task { @MainActor in await viewModel.saveSupportReport(to: outputURL) }
    try? await Task.sleep(nanoseconds: 10_000_000)
    await viewModel.loadSupportDiagnostics()
    await report.value

    let reportState = await MainActor.run { viewModel.supportReportState }
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
  var diagnosticsReadCount = 0

  init(
    statusPayload: ApplicationServiceStatusPayload = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "ready",
      compatibilityIdentity: CompatibilityIdentity.sdl2_3.rawValue
    ),
    diagnosticsPayloads: [ApplicationServiceVirtualDeviceDiagnosticsPayload] = [
      ApplicationServiceVirtualDeviceDiagnosticsPayload(
        userSpaceVirtualDeviceEnabled: true,
        userSpaceVirtualDeviceStatus: "ready",
        hidGamepads: []
      )
    ],
    diagnosticsDelayNanoseconds: [UInt64] = [],
    diagnosticsShouldFail: Bool = false
  ) {
    self.statusPayload = statusPayload
    self.diagnosticsPayloads =
      diagnosticsPayloads.isEmpty
      ? [
        ApplicationServiceVirtualDeviceDiagnosticsPayload(
          userSpaceVirtualDeviceEnabled: true,
          userSpaceVirtualDeviceStatus: "ready",
          hidGamepads: []
        )
      ] : diagnosticsPayloads
    self.diagnosticsDelayNanoseconds = diagnosticsDelayNanoseconds
    self.diagnosticsShouldFail = diagnosticsShouldFail
  }

  func status() throws -> ApplicationServiceStatusPayload { statusPayload }

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

  func requestPermissions() throws -> PermissionManager.Snapshot {
    PermissionManager.Snapshot(inputMonitoring: .granted, accessibility: .granted)
  }

  func requestPermission(_ requirement: PermissionManager.Requirement) throws
    -> PermissionManager.Snapshot
  { try requestPermissions() }

  func deviceInputState(for _: RuntimeDeviceSelector) throws -> DeviceInputState? { nil }

  func packetLog(for _: RuntimeDeviceSelector) throws -> [PacketLogEntry] { [] }

  func remappingSnapshot() throws -> ApplicationServiceRemappingSnapshotPayload {
    ApplicationServiceRemappingSnapshotPayload(
      profiles: [],
      activeProfiles: [],
      routes: [],
      postEventAccess: .granted
    )
  }

  func remappingProfile(id: UUID) throws -> RemappingProfile {
    throw ApplicationServiceClientError.invalidResponse
  }

  func createRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { try remappingSnapshot() }

  func updateRemappingProfile(_ profile: RemappingProfile, expectedCurrent: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { try remappingSnapshot() }

  func importRemappingProfile(_ profile: RemappingProfile) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { try remappingSnapshot() }

  func deleteRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    try remappingSnapshot()
  }

  func activateRemappingProfile(id: UUID) throws -> ApplicationServiceRemappingSnapshotPayload {
    try remappingSnapshot()
  }

  func deactivateRemappingProfile(vendorID: UInt16, productID: UInt16) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { try remappingSnapshot() }

  func deactivateRemappingProfile(profileID: UUID) throws
    -> ApplicationServiceRemappingSnapshotPayload
  { try remappingSnapshot() }

  func remappingPostEventAccess() throws -> RemappingPostEventAccessState { .granted }

  func requestRemappingPostEventAccess() throws -> RemappingPostEventAccessState { .granted }

  func compatibilityIdentity() throws -> CompatibilityIdentity { .sdl2_3 }

  func setCompatibilityIdentity(_ identity: CompatibilityIdentity) throws -> Bool { true }
}
