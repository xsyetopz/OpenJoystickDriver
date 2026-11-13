import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverPresentation

struct ControllerActionsTests {
  private static func device(
    portKey: ControllerPortKey? = nil,
    override: VirtualHIDProfileID? = nil,
    scope: VirtualHIDProfileOverrideScope? = nil
  ) -> ApplicationServiceDeviceDescription {
    var device = ApplicationServiceDeviceDescription(
      name: "Test Pad",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system,
      sessionToken: .fixture("actions-device"),
      portKey: portKey
    )
    device.virtualHIDProfile = ApplicationServiceVirtualHIDProfileStatus(
      profile: override,
      source: override == nil ? nil : .override,
      override: override,
      overrideScope: scope,
      unavailable: false
    )
    return device
  }

  // MARK: Scope

  @Test
  func unitScopeIsOfferedOnlyWithUnitID() {
    #expect(VirtualHIDProfileScopeChoice.offered(for: Self.device()) == [.model])
    #expect(
      VirtualHIDProfileScopeChoice.offered(for: Self.device(portKey: .fixture("port-1")))
        == [.model, .unit]
    )
  }

  @Test
  func initialScopeFollowsStoredOverride() {
    let port = ControllerPortKey.fixture("port-1")
    #expect(VirtualHIDProfileScopeChoice.initial(for: Self.device(portKey: port)) == .model)
    #expect(
      VirtualHIDProfileScopeChoice.initial(
        for: Self.device(portKey: port, override: .generic, scope: .unit)
      ) == .unit
    )
    #expect(
      VirtualHIDProfileScopeChoice.initial(
        for: Self.device(portKey: port, override: .generic, scope: .model)
      ) == .model
    )
    #expect(
      VirtualHIDProfileScopeChoice.initial(for: Self.device(override: .generic, scope: .unit))
        == .model
    )
    #expect(VirtualHIDProfileScopeChoice.unit.scope == .unit)
    #expect(VirtualHIDProfileScopeChoice.model.scope == .model)
  }

  @Test
  @MainActor
  func overrideRequestCarriesChosenScope() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    let device = Self.device(portKey: .fixture("port-1"))

    await viewModel.setVirtualHIDProfileOverride(.generic, for: device, scope: .unit)
    await viewModel.setVirtualHIDProfileOverride(nil, for: device, scope: .unit)
    await viewModel.setVirtualHIDProfileOverride(.generic, for: device)

    let requests = await gateway.overrideRequests
    #expect(requests.map(\.scope) == [.unit, .unit, .model])
  }

  @Test
  @MainActor
  func resetAllReportsServiceRefusal() async {
    let gateway = GatewayStub()
    let viewModel = RuntimeViewModel(gateway: gateway)
    #expect(await viewModel.resetAllVirtualHIDProfileOverrides() == nil)
    await gateway.setResetAllResult(false)
    #expect(
      await viewModel.resetAllVirtualHIDProfileOverrides()
        == OJDLocalized.string("ui.controllers.virtual.resetAllFailed")
    )
    #expect(await gateway.resetAllRequestCount == 2)
  }

  // MARK: Export

  @Test
  func exportNamesFileByProfileAndFormat() {
    #expect(
      VirtualGamepadExport.fileName(format: .sdl, profile: .sdlCompatible)
        == "sdl-compatible-sdl.txt"
    )
    #expect(
      VirtualGamepadExport.fileName(format: .w3c, profile: .sdlCompatible)
        == "sdl-compatible-w3c.json"
    )
  }

  @Test
  func exportDocumentIsMappingCommandPrints() throws {
    let mapping = try VirtualHIDProfileID.generic.gamepadMapping()
    let sdl = try VirtualGamepadExport.document(format: .sdl, profile: .generic)
    #expect(sdl.hasSuffix(mapping.sdlMapping + "\n"))
    let w3c = try VirtualGamepadExport.document(format: .w3c, profile: .generic)
    let decoded = try JSONSerialization.jsonObject(with: Data(w3c.utf8)) as? [[String: Any]]
    #expect(decoded?.count == 1)
    #expect(decoded?.first?["id"] as? String == mapping.w3cID)
  }

  @Test
  func exportNeedsSelectedProfile() {
    #expect(VirtualGamepadExport.profile(for: Self.device(override: .generic)) == .generic)
    var system = Self.device()
    system = ApplicationServiceDeviceDescription(
      name: "Native",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .systemGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
    )
    #expect(VirtualGamepadExport.profile(for: system) == nil)
  }

  @Test
  func overrideDecisionSkipsOnlyWhenProfileAndScopeAlreadyMatch() {
    let port = ControllerPortKey.fixture("port-1")
    let model = Self.device(portKey: port, override: .generic, scope: .model)
    let unit = Self.device(portKey: port, override: .generic, scope: .unit)
    let none = Self.device(portKey: port)
    typealias Decision = VirtualHIDProfileOverrideDecision
    #expect(Decision.decide(profile: .generic, scope: .model, for: model) == .unchanged)
    #expect(Decision.decide(profile: .generic, scope: .unit, for: model) == .send)
    #expect(Decision.decide(profile: .sdlCompatible, scope: .model, for: model) == .send)
    #expect(Decision.decide(profile: .generic, scope: .unit, for: unit) == .unchanged)
    #expect(Decision.decide(profile: .generic, scope: .model, for: unit) == .send)
    #expect(Decision.decide(profile: .generic, scope: .model, for: none) == .send)
  }

  @Test
  func automaticInScopeWithoutOverrideNamesScopeThatHoldsIt() {
    let port = ControllerPortKey.fixture("port-1")
    let model = Self.device(portKey: port, override: .generic, scope: .model)
    let unit = Self.device(portKey: port, override: .generic, scope: .unit)
    typealias Decision = VirtualHIDProfileOverrideDecision
    #expect(Decision.decide(profile: nil, scope: .model, for: model) == .send)
    #expect(Decision.decide(profile: nil, scope: .unit, for: model) == .otherScopeHolds(.model))
    #expect(Decision.decide(profile: nil, scope: .unit, for: unit) == .send)
    #expect(Decision.decide(profile: nil, scope: .model, for: unit) == .otherScopeHolds(.unit))
    #expect(
      Decision.decide(profile: nil, scope: .model, for: Self.device(portKey: port)) == .unchanged
    )
    #expect(Decision.currentScope(for: model) == .model)
    #expect(Decision.currentScope(for: Self.device(portKey: port)) == nil)
  }

  @Test
  func gameEnvironmentDropsVariablesOnlyLaunchdSets() {
    let environment = VirtualGamepadLaunch.gameEnvironment(from: [
      "__CFBundleIdentifier": "app", "XPC_SERVICE_NAME": "x", "XPC_FLAGS": "0x0",
      "LaunchInstanceID": "1", "OS_ACTIVITY_DT_MODE": "YES", "PATH": "/usr/bin", "HOME": "/h",
    ])
    #expect(environment == ["PATH": "/usr/bin", "HOME": "/h"])
  }

  @Test
  func profilesNeedingBackendAreThoseSDLDoesNotRecognize() throws {
    let devices = VirtualHIDProfileID.allCases.map { Self.device(override: $0) }
    let expected = try VirtualHIDProfileID.allCases.filter {
      try !$0.gamepadMapping().worksWithDefaultSDLHints
    }
    #expect(try VirtualGamepadLaunch.profilesNeedingBackend(in: devices) == expected)
  }

  // MARK: Launch

  @Test
  func launchWithoutVirtualGamepadIsRefused() {
    let system = ApplicationServiceDeviceDescription(
      name: "Native",
      vendorID: 1,
      productID: 2,
      protocolBinding: ProtocolBindingID(.hidDescriptor),
      connection: "USB",
      discoverySource: .hid,
      physicalOwnership: .systemGamepad,
      serialNumber: nil,
      bindingResult: .hidDescriptorFixture,
      recordServer: .system,
      recordAccessRoute: .system
    )
    #expect(throws: VirtualGamepadLaunch.Failure.noGamepad) {
      try VirtualGamepadLaunch.prepare(
        program: URL(fileURLWithPath: "/bin/echo"),
        devices: [system],
        gameControllerBackend: false,
        baseEnvironment: [:]
      )
    }
  }

  @Test
  func launchSetsMappingAndBackendHints() throws {
    let prepared = try VirtualGamepadLaunch.prepare(
      program: URL(fileURLWithPath: "/bin/echo"),
      devices: [Self.device(override: .generic)],
      gameControllerBackend: true,
      baseEnvironment: ["KEEP": "1"]
    )
    #expect(prepared.executable.path == "/bin/echo")
    #expect(prepared.environment["KEEP"] == "1")
    #expect(
      prepared.environment[SDLLaunchEnvironment.variable]?.contains(
        try VirtualHIDProfileID.generic.gamepadMapping().sdlMapping
      ) == true
    )
    #expect(prepared.environment["SDL_JOYSTICK_HIDAPI"] == "0")
  }

  @Test
  func launchOfNonExecutableFileSaysWhy() {
    #expect(
      throws: VirtualGamepadLaunch.Failure.cannotStart(
        program: "missing",
        reason: OJDLocalized.string("cli.virtual.launch.errorNotExecutable")
      )
    ) {
      try VirtualGamepadLaunch.prepare(
        program: URL(fileURLWithPath: "/nonexistent/missing"),
        devices: [Self.device(override: .generic)],
        gameControllerBackend: false,
        baseEnvironment: [:]
      )
    }
  }

  @Test
  @MainActor
  func launchStartsProgramAndReportsItsExit() async throws {
    let actions = ControllerDetailActions()
    actions.launch(
      program: URL(fileURLWithPath: "/usr/bin/true"),
      devices: [Self.device(override: .generic)],
      gameControllerBackend: false,
      baseEnvironment: [:]
    )
    for _ in 0..<100 {
      if case .exited = actions.launchOutcome { break }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(actions.launchOutcome == .exited(program: "true", status: 0))
  }

  // MARK: Duration and capture

  @Test
  func durationNeedsFinitePositiveNumber() {
    let locale = Locale(identifier: "en_US")
    #expect(CaptureDuration.parse("10", locale: locale) == 10)
    #expect(CaptureDuration.parse(" 2.5 ", locale: locale) == 2.5)
    #expect(CaptureDuration.parse("0", locale: locale) == nil)
    #expect(CaptureDuration.parse("-3", locale: locale) == nil)
    #expect(CaptureDuration.parse("soon", locale: locale) == nil)
    #expect(CaptureDuration.parse("", locale: locale) == nil)
    #expect(CaptureDuration.parse("2,5", locale: Locale(identifier: "de_DE")) == 2.5)
    #expect(CaptureDuration.text(for: 10, locale: locale) == "10")
  }

  private static func packet(
    _ time: Double,
    _ direction: PacketLogDirection,
    _ hex: String
  )
    -> PacketLogEntry
  {
    let length = hex.split(separator: " ").count
    let json = """
      {"timestamp":\(time),"direction":"\(direction.rawValue)","hex":"\(hex)","length":\(length)}
      """
    return try! JSONDecoder().decode(PacketLogEntry.self, from: Data(json.utf8))
  }

  private final class Clock: @unchecked Sendable {
    private(set) var now: UInt64 = 0
    func advance(_ nanoseconds: UInt64) { now += nanoseconds }
  }

  private final class Snapshots: @unchecked Sendable {
    var reads: [[PacketLogEntry]]
    private(set) var count = 0
    init(_ reads: [[PacketLogEntry]]) { self.reads = reads }
    func next() -> [PacketLogEntry] {
      defer { count += 1 }
      return reads[min(count, reads.count - 1)]
    }
  }

  @Test
  func captureCollectsOnlyPacketsThatArriveWhileItRuns() async throws {
    let before = Self.packet(1, .received, "01")
    let first = Self.packet(2, .received, "02 03")
    let second = Self.packet(3, .transmitted, "04")
    let snapshots = Snapshots([[before], [before, first], [before, first, second]])
    let clock = Clock()
    let packets = try await ControllerPacketCapture.collect(
      seconds: 0.05,
      read: { snapshots.next() },
      uptime: { clock.now },
      sleep: { clock.advance($0) }
    )
    #expect(packets.map(\.hex) == ["02 03", "04"])
    #expect(clock.now >= 50_000_000)
  }

  @Test
  func capturePropagatesReadFailure() async {
    struct Failure: Error {}
    await #expect(throws: Failure.self) {
      try await ControllerPacketCapture.collect(seconds: 1) { throw Failure() }
    }
  }

  @Test
  func captureExportIsJSONDeveloperToolsExport() throws {
    let data = try ControllerPacketCapture.exportData([Self.packet(2, .received, "02 03")])
    let decoded = try JSONDecoder().decode([PacketLogEntry].self, from: data)
    #expect(decoded.map(\.hex) == ["02 03"])
    #expect(
      ControllerPacketCapture.fileName(for: Self.device())
        == "OpenJoystickDriver-packets-1234-5678.json"
    )
  }

  @Test
  func recordDraftNeedsReadableLayout() {
    #expect(ControllerRecordDrafting.fileName(for: Self.device()) == "1234-5678.plist")
    let packets = [Self.packet(1, .received, "00 10 20"), Self.packet(2, .received, "00 11 20")]
    let draft = try? ControllerRecordDrafting.draft(
      for: Self.device(),
      packets: packets,
      descriptor: nil
    )
    #expect(draft?.capturedReports == 2)
  }

  @Test
  @MainActor
  func timedCaptureOfNothingReportsNoPackets() async throws {
    let actions = ControllerDetailActions()
    actions.startTimed(
      .capturePackets,
      device: Self.device(),
      gateway: GatewayStub(),
      seconds: 0.05
    ) { nil }
    for _ in 0..<100 {
      if case .failed = actions.timedState { break }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    #expect(
      actions.timedState
        == .failed(OJDLocalized.string("cli.controller.capture.noPackets"))
    )
    #expect(actions.pendingSave == nil)
  }

  @Test
  @MainActor
  func savingWritesPendingFile() throws {
    let actions = ControllerDetailActions()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ojd-mapping-\(UUID().uuidString).txt"
    )
    defer { try? FileManager.default.removeItem(at: url) }
    actions.exportMapping(format: .sdl, profile: .generic, to: url)
    #expect(
      try String(contentsOf: url, encoding: .utf8)
        == (try VirtualGamepadExport.document(format: .sdl, profile: .generic))
    )
    #expect(actions.notice?.source == .exportMapping)
    #expect(actions.notice?.isError == false)
    actions.exportMapping(
      format: .sdl,
      profile: .generic,
      to: URL(fileURLWithPath: "/nonexistent-dir/mapping.txt")
    )
    #expect(actions.notice?.isError == true)
  }
}
