import Foundation
import OpenJoystickDriverKit

/// One controller in `ojd controller list --json`.
///
/// The serial number is never printed; `hasSerialNumber` says whether the controller reports one.
struct ControllerSummary: Encodable, Equatable {
  let id: String
  let name: String
  let vendorID: Int
  let productID: Int
  let connection: String
  let `protocol`: String
  let session: String
  let hasSerialNumber: Bool

  init(_ device: ApplicationServiceDeviceDescription) {
    id = device.runtimeIdentifier
    name = device.name
    vendorID = Int(device.vendorID)
    productID = Int(device.productID)
    connection = device.connection
    self.protocol = device.protocolBinding.rawValue
    session = device.sessionState.rawValue
    hasSerialNumber = device.serialNumber.map { !$0.isEmpty } ?? false
  }
}

/// The `ojd controller list --json` result.
struct ControllerListReport: Encodable, Equatable { let controllers: [ControllerSummary] }

/// The `ojd controller show --json` result.
struct ControllerShowReport: Encodable, Equatable {
  struct Ownership: Encodable, Equatable {
    let discoverySource: String
    let physical: String
    let hidInput: String
    let duplicateExposureRisk: String
  }

  struct InputHealth: Encodable, Equatable {
    let state: String
    let reportFormat: String?
    let failureReason: String?
    let recoveryCount: Int
  }

  struct Capabilities: Encodable, Equatable {
    let controls: [String]
    let touchContactCount: Int
    let motion: Bool
    let rumbleMotors: [String]
    let binaryRumbleMotors: [String]
    let lightingFeatures: [String]
    let adaptiveTriggers: [String]
  }

  struct Virtual: Encodable, Equatable {
    let profile: String?
    let source: String?
    let override: String?
    let unavailable: Bool
  }

  struct OutputCheck: Encodable, Equatable {
    let id: String
    let command: String
    let expected: String
  }

  struct Detail: Encodable, Equatable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let connection: String
    let `protocol`: String
    let interfaceNumber: Int?
    let hasSerialNumber: Bool
    let session: String
    let startupCommandStatus: String?
    let inputHealth: InputHealth
    let ownership: Ownership
    let quirks: [String]
    let capabilities: Capabilities
    let virtual: Virtual?
    let outputChecks: [OutputCheck]
  }

  let controller: Detail

  init(_ device: ApplicationServiceDeviceDescription) {
    let output = device.physicalOutputCapabilities
    controller = Detail(
      id: device.runtimeIdentifier,
      name: device.name,
      vendorID: Int(device.vendorID),
      productID: Int(device.productID),
      connection: device.connection,
      protocol: device.protocolBinding.rawValue,
      interfaceNumber: device.interfaceNumber.map(Int.init),
      hasSerialNumber: device.serialNumber.map { !$0.isEmpty } ?? false,
      session: device.sessionState.rawValue,
      startupCommandStatus: device.startupCommandStatus,
      inputHealth: InputHealth(
        state: device.inputHealth.state.rawValue,
        reportFormat: device.inputHealth.reportFormat,
        failureReason: device.inputHealth.failureReason?.rawValue,
        recoveryCount: device.inputHealth.recoveryCount
      ),
      ownership: Ownership(
        discoverySource: device.discoverySource.rawValue,
        physical: device.physicalOwnership.rawValue,
        hidInput: device.hidInputOwnership.rawValue,
        duplicateExposureRisk: device.duplicateExposureRisk.rawValue
      ),
      quirks: device.quirks,
      capabilities: Capabilities(
        controls: ControlID.allCases.filter(device.capabilities.controls.contains).map(\.rawValue),
        touchContactCount: Int(device.capabilities.touchContactCount),
        motion: device.capabilities.motion,
        rumbleMotors: output.rumbleMotors.map(\.rawValue),
        binaryRumbleMotors: output.binaryRumbleMotors.map(\.rawValue),
        lightingFeatures: output.lightingFeatures.map(\.rawValue),
        adaptiveTriggers: output.adaptiveTriggers.map(\.rawValue)
      ),
      virtual: device.virtualHIDProfile.map {
        Virtual(
          profile: $0.profile?.rawValue,
          source: $0.source,
          override: $0.override?.rawValue,
          unavailable: $0.unavailable
        )
      },
      outputChecks: PhysicalOutputValidationPlan(device: device).steps.map {
        OutputCheck(id: $0.id, command: $0.command, expected: $0.expectedObservation)
      }
    )
  }
}
