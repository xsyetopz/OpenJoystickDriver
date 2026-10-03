import Foundation
import OpenJoystickDriverKit

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
    /// `unit` or `model`: which choice `override` is.
    let overrideScope: String?
    let unavailable: Bool
  }

  /// Whether a virtual device publishes the controller, and why not.
  struct Publication: Encodable, Equatable {
    let state: String
    let reason: String?
    let target: String?
    /// System uptime in nanoseconds of the last send to the virtual device.
    let lastAttemptedNanoseconds: UInt64?
    /// System uptime in nanoseconds of the last send the virtual device accepted.
    let lastCompletedNanoseconds: UInt64?
  }

  /// The effective record for the controller's model, in the layer and file shape of `record list`.
  struct Record: Encodable, Equatable {
    let layer: String
    let file: String?

    init(_ record: ControllerRecord) {
      layer = record.layer.rawValue
      file = record.userFile?.path
    }
  }

  struct OutputCheck: Encodable, Equatable {
    let id: String
    let command: String
    let expected: String
  }

  struct Detail: Encodable, Equatable {
    let id: String
    let unit: String?
    let name: String
    let vendorID: Int
    let productID: Int
    let connection: String
    let `protocol`: String
    let interfaceNumber: Int?
    let hasSerialNumber: Bool
    let session: String
    /// Absent when the service reports no power state.
    let power: ControllerConnectionState.Power?
    let startupCommandStatus: String?
    let inputHealth: InputHealth
    let ownership: Ownership
    let quirks: [String]
    let record: Record?
    let capabilities: Capabilities
    let virtual: Virtual?
    let publication: Publication?
    let outputChecks: [OutputCheck]
  }

  let controller: Detail

  /// `record` is the effective record of the device's model, if there is one.
  /// `sharesModel` is whether another connected controller has the same VID:PID, so the output
  /// checks must name this one by its ID.
  init(
    _ device: ApplicationServiceDeviceDescription,
    record: ControllerRecord?,
    sharesModel: Bool = false
  ) {
    let output = device.physicalOutputCapabilities
    controller = Detail(
      id: device.runtimeIdentifier,
      unit: device.unitIdentifier,
      name: device.name,
      vendorID: Int(device.vendorID),
      productID: Int(device.productID),
      connection: device.connection,
      protocol: device.protocolBinding.rawValue,
      interfaceNumber: device.interfaceNumber.map(Int.init),
      hasSerialNumber: device.serialNumber.map { !$0.isEmpty } ?? false,
      session: device.sessionState.rawValue,
      power: device.connectionState?.power,
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
      record: record.map(Record.init),
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
          overrideScope: $0.overrideScope,
          unavailable: $0.unavailable
        )
      },
      publication: device.publication.map {
        Publication(
          state: $0.state.rawValue,
          reason: $0.reason,
          target: $0.target?.rawValue,
          lastAttemptedNanoseconds: $0.lastAttemptedNanoseconds,
          lastCompletedNanoseconds: $0.lastCompletedNanoseconds
        )
      },
      outputChecks: PhysicalOutputValidationPlan(
        device: device,
        selector: sharesModel ? device.runtimeIdentifier : nil
      ).steps.map {
        OutputCheck(id: $0.id, command: $0.command, expected: $0.expectedObservation)
      }
    )
  }
}
