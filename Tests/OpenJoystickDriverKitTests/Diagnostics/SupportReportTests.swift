import Foundation
import OpenJoystickDriverKit
import Testing

struct SupportReportTests {
  @Test
  func gameControllerProbeDurationIsFiniteAndPredictablyClamped() {
    #expect(
      GameControllerProbeConfiguration.boundedSeconds(0)
        == GameControllerProbeConfiguration.minimumSeconds
    )
    #expect(
      GameControllerProbeConfiguration.boundedSeconds(10_000)
        == GameControllerProbeConfiguration.maximumSeconds
    )
    #expect(GameControllerProbeConfiguration.boundedSeconds(5) == 5)
  }

  @Test
  func reportExcludesSensitiveAndFreeFormDiagnosticValues() throws {
    let secretSerial = "SERIAL-SECRET-123"
    let secretPath = "/Users/alice/private/controller.txt"
    let status = ApplicationServiceStatusPayload(
      inputRead: .granted,
      inputInject: .granted,
      connectedDevices: [
        ApplicationServiceDeviceDescription(
          name: "Test Controller",
          vendorID: 1234,
          productID: 5678,
          protocolBinding: ProtocolBindingID(.xboxGIP, variant: .usb),
          connection: "USB",
          discoverySource: .rawUSB,
          serialNumber: secretSerial,
          parameters: ["layout=JoyConLeft"],
          bindingResult: .hidDescriptorFixture,
          inputEndpoint: 129,
          outputEndpoint: 2,
          needsSetConfiguration: true,
          postHandshakeSettleMs: 50,
          preferredBackends: ["driverKit"],
          physicalOutputCapabilities: PhysicalControllerOutputCapabilities(rumbleMotors: [
            .lowFrequency, .highFrequency, .leftTrigger, .rightTrigger,
          ]),
          recordServer: .system,
          recordAccessRoute: .system,
          connectionState: ControllerConnectionState(
            transport: .usb,
            backend: .usbExtension,
            isConnected: true,
            power: ControllerConnectionState.Power(
              charging: .discharging,
              battery: BatteryLevel(percentage: 30...39),
              wiredPower: false
            )
          )
        )
      ],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .error(secretPath)
    )
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: .error(secretPath),
      hidGamepads: [
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 1234,
          productID: 5678,
          product: "Test Controller",
          transport: "USB",
          locationID: 3_735_928_559,
          serialKind: .present,
          ioUserClass: "IOHIDDevice",
          isOJDUserSpace: false,
          isGameControllerSupported: true
        ),
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 4321,
          productID: 8765,
          product: "Other Controller",
          transport: "Bluetooth",
          locationID: 4_294_967_294,
          serialKind: .none,
          ioUserClass: "IOHIDDevice",
          isOJDUserSpace: false,
          isGameControllerSupported: false
        ),
      ]
    )
    let health = ApplicationServiceManager.ApplicationServiceHealth(
      installed: true,
      activeCount: 1,
      state: "running"
    )
    let appleAudit = SystemGamepadSupportAuditor.audit(
      snapshot: SystemGamepadCatalogSnapshot(
        source: .downloadedMobileAsset,
        bundleVersions: ["10.5.2"],
        entries: [
          SystemGamepadCatalogEntry(
            vendorID: 1_234,
            productID: 5_678,
            identifiers: ["test.controller"]
          )
        ]
      ),
      records: [
        ControllerModelID(vendorID: 1_234, productID: 5_678)
      ]
    )
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "0.5.0-beta.4",
        appBundleVersion: "1.4.89",
        sourceCommit: String(repeating: "a", count: 40),
        sourceState: .clean
      ),
      osName: "macOS",
      osVersion: "26.0.0",
      architecture: "arm64",
      inputRead: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: health,
      systemGamepadAudit: appleAudit,
      status: status,
      virtualDiagnostics: diagnostics
    )
    let data = try report.encodedJSON()
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains(secretSerial))
    #expect(!json.contains(secretPath))
    #expect(!json.contains("3735928559"))
    #expect(report.data.privacy.includesRawSerialNumbers == false)
    #expect(report.data.privacy.includesFilesystemPaths == false)
    #expect(report.data.privacy.includesPacketPayloads == false)
    #expect(report.data.privacy.includesHIDLocationIDs == false)
    #expect(report.data.controllers.first?.serialNumberPresent == true)
    #expect(report.data.controllers.first?.physicalOutputCapabilities.supportsTriggerRumble == true)
    let power = report.data.controllers.first?.connectionState?.power
    #expect(power?.battery == BatteryLevel(percentage: 30...39))
    #expect(power?.charging == .discharging)
    #expect(report.data.hidGamepads.first?.product == "Test Controller")
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["specversion"] as? String == "1.0")
    #expect(object["id"] as? String == report.id)
    #expect(object["source"] as? String == SupportReport.source)
    #expect(object["type"] as? String == SupportReport.supportDiagnosticType)
    #expect(object["time"] as? String == "1970-01-01T00:00:00Z")
    #expect(object["datacontenttype"] as? String == "application/json")
    #expect(object["dataschema"] as? String == SupportReport.dataSchema)
    #expect(object["$schema"] == nil)
    #expect(object["reportType"] == nil)
    #expect(object["schemaVersion"] == nil)
    let payload = try #require(object["data"] as? [String: Any])
    #expect(payload["apiVersion"] as? String == OpenJoystickDriverAPI.version)
    #expect(payload["kind"] as? String == "SupportDiagnostic")
    _ = try #require(payload["hidGamepads"] as? [[String: Any]])
    let controllers = payload["controllers"] as? [[String: Any]]
    let encodedPower = (controllers?.first?["connectionState"] as? [String: Any])?["power"]
    let encodedBattery = (encodedPower as? [String: Any])?["battery"] as? [String: Any]
    #expect(encodedBattery?["percentage"] as? [Int] == [30, 39])
    let system = try #require(payload["system"] as? [String: Any])
    let buildIdentity = try #require(system["buildIdentity"] as? [String: Any])
    #expect(buildIdentity["appBundleVersion"] as? String == "1.4.89")
    #expect(buildIdentity["sourceCommit"] as? String == String(repeating: "a", count: 40))
    #expect(report.data.systemGamepadAudit?.catalogListedOJDRecordCount == 1)

    let decoded = try JSONDecoder().decode(SupportReport.self, from: data)
    #expect(decoded.specversion == "1.0")
    #expect(decoded.source == SupportReport.source)
    #expect(decoded.type == SupportReport.supportDiagnosticType)
    #expect(decoded.dataschema == SupportReport.dataSchema)
  }

  @Test
  func unavailableServiceProducesExplicitPartialReport() {
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      buildIdentity: BuildIdentity(
        semanticVersion: "test",
        appBundleVersion: "test",
        sourceCommit: "unknown",
        sourceState: .unknown
      ),
      osName: "macOS",
      osVersion: "26.0.0",
      architecture: "arm64",
      inputRead: .denied,
      applicationServiceInstalled: false,
      applicationServiceConnected: false,
      applicationServiceHealth: nil,
      status: nil,
      virtualDiagnostics: nil
    )

    #expect(report.specversion == "1.0")
    #expect(report.type == SupportReport.supportDiagnosticType)
    #expect(report.data.controllers.isEmpty)
    #expect(report.data.hidGamepads.isEmpty)
    #expect(report.data.notes.count >= 2)
    #expect(report.data.notes.allSatisfy { !$0.isEmpty })
  }
}
