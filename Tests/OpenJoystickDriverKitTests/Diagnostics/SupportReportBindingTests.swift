import Foundation
import OpenJoystickDriverTestSupport
import Testing

@testable import OpenJoystickDriverKit

struct SupportReportBindingTests {
  private static let catalog = DeviceCatalog()
  private static let timings = ControllerFrameTimings.fixture

  @Test
  func boundControllerReportsItsRuleAndCatalogRecord() throws {
    // 045E:028E is a catalogued raw-USB XUSB row.
    let classification = ProtocolClassifier.classify(
      PhysicalDevice(vendorID: 0x045E, productID: 0x028E),
      backend: .rawUSB,
      catalog: Self.catalog
    )
    guard case .bound(let binding) = classification else {
      Issue.record("expected a binding, got \(classification)")
      return
    }
    let interface = PhysicalInterfaceSignature(
      interfaceNumber: 0,
      interfaceClass: 0xFF,
      interfaceSubclass: 0x5D,
      interfaceProtocol: 0x01,
      hostTransport: .usb
    )
    let result = ProtocolBindingResult(binding: binding, interfaces: [interface])
    let controller = try #require(
      report(connected: [description(binding: binding, result: result)]).data.controllers.first
    )

    #expect(controller.protocolBinding == "XboxXUSB:Wired")
    let reported = controller.binding
    #expect(reported.outcome == .bound)
    #expect(reported.reason == nil)
    #expect(reported.rule == .catalogRecord)
    #expect(reported.matchedPredicates == [.catalogIdentity, .catalogAccessPath])
    #expect(reported.catalogRecordID == "045e-028e")
    #expect(reported.accessBackend == .rawUSB)
    #expect(reported.interfaces == [ProtocolBindingResult.InterfaceSummary(interface)])
    #expect(reported.rejectedCandidates.isEmpty)
  }

  @Test
  func unboundDeviceReportsItsUnsupportedReason() throws {
    let unbound = ApplicationServiceUnboundDevice(
      vendorID: 0x1234,
      productID: 0x5678,
      connection: "USB",
      accessBackend: .hid,
      reason: .descriptorContractMismatch,
      rejectedCandidates: [],
      interfaces: [ProtocolBindingResult.InterfaceSummary(hostHIDInterface(.usb))]
    )
    let device = try #require(report(unbound: [unbound]).data.unboundDevices.first)

    #expect((device.vendorID, device.productID, device.connection) == (0x1234, 0x5678, "USB"))
    #expect(device.binding.outcome == .unsupported)
    #expect(device.binding.reason == .descriptorContractMismatch)
    #expect(device.binding.rule == nil)
    #expect(device.binding.matchedPredicates.isEmpty)
    #expect(device.binding.catalogRecordID == nil)
    #expect(device.binding.interfaces.map(\.hostTransport) == [.usb])
  }

  @Test
  func bindingResultCarriesNoSerialOrInputState() throws {
    let secretSerial = "SERIAL-SECRET-456"
    let binding = ProtocolBinding(
      protocolID: .hidDescriptor,
      variant: nil,
      accessBackend: .hid,
      interfaceNumber: 0,
      rule: .hidDescriptor,
      matchedPredicates: [.hidDescriptorContract],
      record: nil
    )
    let result = ProtocolBindingResult(
      binding: binding,
      interfaces: [gamepadHIDInterface(host: .usb)]
    )
    let connected = ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x1234,
      productID: 0x5678,
      protocolBinding: binding.id,
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: secretSerial,
      bindingResult: result,
      recordServer: .system,
      recordAccessRoute: .system
    )
    let data = try report(connected: [connected]).encodedJSON()
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(!json.contains(secretSerial))

    let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
    let keys = try #require(encoded as? [String: Any]).keys
    #expect(
      Set(keys) == [
        "outcome", "accessBackend", "interfaces", "rule", "matchedPredicates", "rejectedCandidates",
      ]
    )
    let interfaceKeys = try #require((encoded as? [String: Any])?["interfaces"] as? [[String: Any]])
      .flatMap(\.keys)
    // Descriptor metadata only: its fingerprint, never its bytes or report contents.
    #expect(Set(interfaceKeys) == ["hostTransport", "descriptorFingerprint"])
  }

  @Test
  func boundAndUnboundDeviceReportMatchesItsEquivalenceSnapshot() async throws {
    // A signature-bound raw-USB GIP device whose HID interface, observed at the same location,
    // stays unbound with a non-empty rejected-candidate list (see HIDRawUSBDuplicateTests).
    let device = USBTransportDevice(
      route: .rawUSB,
      serviceID: 90,
      vendorID: 0x1234,
      productID: 0x5678,
      locationID: 91
    )
    func observation(_ endpoints: [PhysicalEndpointSignature]?) -> PhysicalDevice {
      PhysicalDevice(
        serviceAddress: device.serviceAddress,
        vendorID: device.vendorID,
        productID: device.productID,
        configurationValue: 1,
        interfaces: [
          PhysicalInterfaceSignature(
            interfaceNumber: 0,
            alternateSetting: 0,
            interfaceClass: 0xFF,
            interfaceSubclass: 0x47,
            interfaceProtocol: 0xD0,
            endpoints: endpoints
          )
        ]
      )
    }
    let backend = ClaimRecordingHIDAccessBackend()
    let provider = SignatureDiscoveryProvider(
      device: device,
      passive: observation(nil),
      configured: observation([
        PhysicalEndpointSignature(address: 0x81, direction: .in, transferType: .interrupt),
        PhysicalEndpointSignature(address: 0x01, direction: .out, transferType: .interrupt),
      ])
    )
    let manager = DeviceManager(
      dispatcher: LoggingOutputDispatcher(),
      installationKey: testPortKeyInstallationKey,
      hidManager: HIDManager(backend: backend),
      usbTransportProvider: provider
    )
    guard case .claimed = await manager.handleUSBDeviceAdded(device, provider: provider) else {
      Issue.record("The raw-USB service was not claimed")
      return
    }
    let hid = HIDDeviceConnection(
      physicalDevice: PhysicalDevice(
        vendorID: 0x1234,
        productID: 0x5678,
        productName: "Test pad",
        transportProperty: "USB",
        physicalLocationIdentifier: 91,
        interfaces: [gamepadHIDInterface(host: .usb)]
      ),
      routingAddress: .ioKit(locationID: 91, interfaceNumber: nil)
    )
    await manager.handleHIDEvent(.connected(connection: hid, ownership: .exclusive))

    let connected = await manager.connectedDeviceDescriptions()
    let unbound = await manager.unboundDeviceDescriptions()
    await manager.stop()

    #expect(connected.map(\.discoverySource) == [.rawUSB])
    let boundInterfaces = try #require(connected.first).bindingResult.interfaces
    #expect(!boundInterfaces.isEmpty)
    let rejectedCandidates = try #require(unbound.first).bindingResult.rejectedCandidates
    #expect(!rejectedCandidates.isEmpty)

    let encoded = try report(
      connected: connected.map(ApplicationServiceDeviceDescription.init(snapshot:)),
      unbound: unbound.map(ApplicationServiceUnboundDevice.init(snapshot:)),
      frameTimings: [Self.timings]
    ).encodedJSON()
    #expect(try EquivalenceSnapshotStore.verify(rendered(encoded), named: Self.snapshotName) == nil)
  }

  @Test
  func reportCarriesTheFiveStageStampsOfEachFrame() throws {
    let decoded = try JSONDecoder().decode(
      SupportReport.self,
      from: report(frameTimings: [Self.timings]).encodedJSON()
    )

    let frame = try #require(decoded.data.frameTimings.first?.frames.first)
    #expect(frame.stages.map(\.stage) == FrameStage.allCases)
    #expect(frame.stages.map(\.nanoseconds) == [100, 150, 200, 260, 900])
  }

  /// `support-report-binding.json` in `Tests/EquivalenceSnapshots`, which
  /// `Tests/RepositoryScripts/test_report_schema.py` validates against `report.schema.json`.
  /// `./Scripts/ojd snapshots write` rewrites it from this test.
  private static let snapshotName = "support-report-binding.json"

  /// The report as the snapshot stores it: sorted members, two-space indent and the CloudEvents
  /// `id`, a fresh UUID on every encode, written as `fixture`.
  private func rendered(_ data: Foundation.Data) throws -> String {
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["id"] = "fixture"
    let text = try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    )
    return try #require(String(data: text, encoding: .utf8)) + "\n"
  }

  private func description(
    binding: ProtocolBinding,
    result: ProtocolBindingResult
  ) -> ApplicationServiceDeviceDescription {
    ApplicationServiceDeviceDescription(
      name: "Test Controller",
      vendorID: 0x045E,
      productID: 0x028E,
      protocolBinding: binding.id,
      connection: "USB",
      discoverySource: .rawUSB,
      serialNumber: nil,
      bindingResult: result,
      recordServer: .system,
      recordAccessRoute: .system
    )
  }

  private func report(
    connected: [ApplicationServiceDeviceDescription] = [],
    unbound: [ApplicationServiceUnboundDevice] = [],
    frameTimings: [ControllerFrameTimings] = []
  ) -> SupportReport {
    SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "0.5.0",
        appBundleVersion: "1",
        sourceCommit: String(repeating: "a", count: 40),
        sourceState: .clean
      ),
      osName: "macOS",
      osVersion: "26.0.0",
      architecture: "arm64",
      inputRead: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: nil,
      frameTimings: frameTimings,
      status: ApplicationServiceStatusPayload(
        inputRead: .granted,
        inputInject: .granted,
        connectedDevices: connected,
        unboundDevices: unbound
      ),
      virtualDiagnostics: nil
    )
  }
}
