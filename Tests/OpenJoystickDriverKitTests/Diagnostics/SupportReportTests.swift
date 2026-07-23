import Foundation
import OpenJoystickDriverKit
import Testing

struct SupportReportTests {
  @Test func reportExcludesSensitiveAndFreeFormDiagnosticValues() throws {
    let secretSerial = "SERIAL-SECRET-123"
    let secretPath = "/Users/alice/private/controller.txt"
    let status = ApplicationServiceStatusPayload(
      inputMonitoring: "granted",
      accessibility: "granted",
      connectedDevices: [
        ApplicationServiceDeviceDescription(
          name: "Test Controller",
          vendorID: 1234,
          productID: 5678,
          parser: "GIP",
          connection: "USB",
          serialNumber: secretSerial,
          protocolVariant: .xboxOne,
          mappingFlags: ["swapAB"],
          inputEndpoint: 129,
          outputEndpoint: 2,
          needsSetConfiguration: true,
          postHandshakeSettleMs: 50,
          preferredBackends: ["driverKit"],
          physicalOutputCapabilities: PhysicalControllerOutputCapabilities(rumbleMotors: [
            .leftMain, .rightMain, .leftTrigger, .rightTrigger,
          ]),
        ),
      ],
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "error: \(secretPath)",
      compatibilityIdentity: "sdl2-3"
    )
    let diagnostics = ApplicationServiceVirtualDeviceDiagnosticsPayload(
      userSpaceVirtualDeviceEnabled: true,
      userSpaceVirtualDeviceStatus: "error: \(secretPath)",
      hidGamepads: [
        ApplicationServiceHIDGamepadSnapshot(
          vendorID: 1234,
          productID: 5678,
          product: "Test Controller",
          transport: "USB",
          locationID: 3_735_928_559,
          serialKind: .present,
          ioUserClass: "IOHIDDevice",
          isOJDDriverKit: false,
          isOJDUserSpace: false,
          isGameControllerSupported: true
        ),
      ],
      driverKitOutputStats: ApplicationServiceDriverKitOutputStats(
        attempts: 4,
        successes: 3,
        failures: 1,
        lastErrorHex: "0xe00002cd",
        connectionAttempts: 2,
        connectionSuccesses: 1,
        connectionFailures: 1,
        lastConnectionErrorHex: "0xe00002c0",
        lastDiscoverySummary: secretPath
      )
    )
    let health = ApplicationServiceManager.ApplicationServiceHealth(
      installed: true,
      activeCount: 1,
      state: "running"
    )
    let appleAudit = AppleGameControllerSupportAuditor.audit(
      snapshot: AppleGameControllerCatalogSnapshot(
        source: .downloadedMobileAsset,
        bundleVersions: ["10.5.2"],
        entries: [
          AppleGameControllerCatalogEntry(
            vendorID: 1_234,
            productID: 5_678,
            identifiers: ["test.controller"]
          ),
        ]
      ),
      records: [
        OJDControllerRecordIdentity(vendorID: 1_234, productID: 5_678, name: "Test Controller")
      ]
    )
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      appVersion: "test",
      macOSVersion: "26.0.0",
      architecture: "arm64",
      inputMonitoring: .granted,
      applicationServiceInstalled: true,
      applicationServiceConnected: true,
      applicationServiceHealth: health,
      appleGameControllerAudit: appleAudit,
      status: status,
      virtualDiagnostics: diagnostics
    )
    let data = try report.encodedJSON()
    let json = try #require(String(data: data, encoding: .utf8))

    #expect(!json.contains(secretSerial))
    #expect(!json.contains(secretPath))
    #expect(!json.contains("3735928559"))
    #expect(report.privacy.includesRawSerialNumbers == false)
    #expect(report.privacy.includesFilesystemPaths == false)
    #expect(report.privacy.includesPacketPayloads == false)
    #expect(report.privacy.includesHIDLocationIDs == false)
    #expect(report.controllers.first?.serialNumberPresent == true)
    #expect(report.controllers.first?.physicalOutputCapabilities.supportsTriggerRumble == true)
    #expect(report.outputValidationPlans.count == 1)
    #expect(report.outputValidationPlans.first?.steps.map(\.id).contains("left-trigger") == true)
    #expect(report.hidGamepads.first?.product == "Test Controller")
    #expect(report.driverKitOutput?.successes == 3)
    #expect(report.appleGameControllerAudit?.catalogListedOJDRecordCount == 1)
  }

  @Test func unavailableServiceProducesAnExplicitPartialReport() {
    let report = SupportReport(
      generatedAt: Date(timeIntervalSince1970: 0),
      appVersion: "test",
      macOSVersion: "26.0.0",
      architecture: "arm64",
      inputMonitoring: .denied,
      applicationServiceInstalled: false,
      applicationServiceConnected: false,
      applicationServiceHealth: nil,
      status: nil,
      virtualDiagnostics: nil
    )

    #expect(report.schemaVersion == SupportReport.currentSchemaVersion)
    #expect(report.controllers.isEmpty)
    #expect(report.hidGamepads.isEmpty)
    #expect(report.notes.contains("Application service status was unavailable."))
    #expect(report.notes.contains("Virtual-device diagnostics were unavailable."))
  }
}
