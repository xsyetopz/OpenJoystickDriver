import Foundation
import OpenJoystickDriverKit
import OpenJoystickDriverService

/// The `ojd status --json` result.
///
/// Keys and enum values are stable identifiers. Fields that only the service can report are
/// absent while it is stopped.
struct StatusReport: Encodable, Equatable {
  struct Service: Encodable, Equatable {
    let state: ServiceStateResult.State
    let version: String?
  }

  struct Extension: Encodable, Equatable {
    enum Bundle: String, Encodable {
      case present
      case missing
      case invalid
    }

    enum Registration: String, Encodable {
      case active
      case inactive
      case absent
      case unavailable
    }

    let bundle: Bundle
    let registration: Registration

    init(_ status: ExtensionStatus) {
      switch status.bundle {
      case .present: bundle = .present
      case .missing: bundle = .missing
      case .invalid: bundle = .invalid
      }
      switch status.registration {
      case .active: registration = .active
      case .inactive: registration = .inactive
      case .absent: registration = .absent
      case .unavailable: registration = .unavailable
      }
    }
  }

  struct Permissions: Encodable, Equatable {
    let inputMonitoring: String
    let accessibility: String
  }

  struct VirtualDevice: Encodable, Equatable {
    let enabled: Bool?
    let status: String?
    let overrideError: String?
  }

  struct Controller: Encodable, Equatable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let connection: String
  }

  struct Device: Encodable, Equatable {
    let vendorID: Int
    let productID: Int
    let connection: String
    let reason: String?
  }

  let service: Service
  let `extension`: Extension
  let permissions: Permissions?
  let virtualDevice: VirtualDevice?
  let controllers: [Controller]?
  let unboundDevices: [Device]?
  let passThroughDevices: [Device]?
  /// User controller records OJD skipped. Read from the files, so present while the service is
  /// stopped.
  let skippedRecords: [SkippedRecord]

  init(
    payload: ApplicationServiceStatusPayload?,
    extensionStatus: ExtensionStatus,
    skippedRecords: [SkippedRecord] = []
  ) {
    self.extension = Extension(extensionStatus)
    self.skippedRecords = skippedRecords
    guard let payload else {
      service = Service(state: .stopped, version: nil)
      permissions = nil
      virtualDevice = nil
      controllers = nil
      unboundDevices = nil
      passThroughDevices = nil
      return
    }
    service = Service(state: .running, version: payload.buildIdentity.semanticVersion)
    permissions = Permissions(
      inputMonitoring: payload.inputMonitoring,
      accessibility: payload.accessibility
    )
    virtualDevice = VirtualDevice(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus?.wireValue,
      overrideError: payload.virtualHIDProfileOverrideError
    )
    controllers = payload.connectedDevices.map {
      Controller(
        id: $0.runtimeIdentifier,
        name: $0.name,
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection
      )
    }
    unboundDevices = payload.unboundDevices.map {
      Device(
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection,
        reason: $0.reason.rawValue
      )
    }
    passThroughDevices = payload.passThroughDevices.map {
      Device(
        vendorID: Int($0.vendorID),
        productID: Int($0.productID),
        connection: $0.connection,
        reason: nil
      )
    }
  }
}

/// `VVVV:PPPP`, the hex identity `ojd` prints and accepts for a USB or Bluetooth device.
func deviceIdentity(vendorID: Int, productID: Int) -> String {
  String(format: "%04X:%04X", vendorID, productID)
}
