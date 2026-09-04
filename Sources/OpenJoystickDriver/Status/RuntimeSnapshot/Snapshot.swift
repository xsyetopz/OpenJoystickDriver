import Foundation
import OpenJoystickDriverKit

enum StatusPermissionState: String, Sendable, Equatable {
  case granted
  case denied
  case unknown
  case unavailable

  init(_ state: PermissionManager.AccessState) {
    switch state {
    case .granted: self = .granted
    case .denied: self = .denied
    case .unknown: self = .unknown
    }
  }

  var accessState: PermissionManager.AccessState? {
    switch self {
    case .granted: return .granted
    case .denied: return .denied
    case .unknown: return .unknown
    case .unavailable: return nil
    }
  }
}

enum CompatibilityOutputState: String, Sendable, Equatable {
  case enabled
  case disabled
  case unavailable
  case error
}

struct RuntimeCompatibilityStatus: Sendable, Equatable {
  let identity: CompatibilityIdentity?
  let diagnostic: String?

  init(rawValue: String?) {
    self.identity = rawValue.flatMap(CompatibilityIdentity.init(rawValue:))
    if let rawValue, identity == nil {
      self.diagnostic = "Unknown compatibility identity: \(rawValue)"
    } else {
      self.diagnostic = nil
    }
  }

  static let unavailable = Self(rawValue: nil)
}

struct ConnectedControllersStatus: Sendable {
  let isAvailable: Bool
  let descriptions: [ApplicationServiceDeviceDescription]

  init(descriptions: [ApplicationServiceDeviceDescription]) {
    self.isAvailable = true
    self.descriptions = descriptions
  }

  private init() {
    self.isAvailable = false
    self.descriptions = []
  }

  static let unavailable = Self()

  var count: Int? { isAvailable ? descriptions.count : nil }
}

struct CompatibilityOutputStatus: Sendable, Equatable {
  let state: CompatibilityOutputState
  let detail: String?
  let diagnostic: String?

  init(enabled: Bool?, status: String?) {
    let normalizedStatus = status?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalizedStatus, normalizedStatus.hasPrefix("error:") {
      self.state = .error
      self.detail = nil
      let message = normalizedStatus.dropFirst("error:".count).trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      self.diagnostic = message.isEmpty ? normalizedStatus : message
      return
    }

    self.detail = normalizedStatus
    self.diagnostic = nil
    switch (enabled, normalizedStatus) {
    case (.some(true), _): self.state = .enabled
    case (.some(false), .some("off")): self.state = .disabled
    default: self.state = .unavailable
    }
  }

  static let unavailable = Self(enabled: nil, status: nil)
}

struct StatusPermissions: Sendable, Equatable {
  let inputMonitoring: StatusPermissionState
  let accessibility: StatusPermissionState

  init(inputMonitoring: StatusPermissionState, accessibility: StatusPermissionState) {
    self.inputMonitoring = inputMonitoring
    self.accessibility = accessibility
  }

  init(_ snapshot: PermissionManager.Snapshot) {
    self.init(
      inputMonitoring: StatusPermissionState(snapshot.inputMonitoring),
      accessibility: StatusPermissionState(snapshot.accessibility)
    )
  }

  init(inputMonitoring: String, accessibility: String) {
    self.init(
      inputMonitoring: StatusPermissionState(
        PermissionManager.AccessState(status: inputMonitoring)
      ),
      accessibility: StatusPermissionState(PermissionManager.AccessState(status: accessibility))
    )
  }

  static let unavailable = Self(inputMonitoring: .unavailable, accessibility: .unavailable)

  var isReady: Bool { inputMonitoring == .granted && accessibility == .granted }

  var isAvailable: Bool { inputMonitoring != .unavailable && accessibility != .unavailable }
}

struct RuntimeStatusSnapshot: Sendable {
  let source: RuntimeStatusSource
  let permissions: StatusPermissions
  let controllers: ConnectedControllersStatus
  let compatibility: RuntimeCompatibilityStatus
  let output: CompatibilityOutputStatus
  let applicationServicePayload: ApplicationServiceStatusPayload?

  init(payload: ApplicationServiceStatusPayload) {
    self.source = .runningApplication
    self.permissions = StatusPermissions(
      inputMonitoring: payload.inputMonitoring,
      accessibility: payload.accessibility
    )
    self.controllers = ConnectedControllersStatus(descriptions: payload.connectedDevices)
    self.compatibility = RuntimeCompatibilityStatus(rawValue: payload.compatibilityIdentity)
    self.output = CompatibilityOutputStatus(
      enabled: payload.userSpaceVirtualDeviceEnabled,
      status: payload.userSpaceVirtualDeviceStatus
    )
    self.applicationServicePayload = payload
  }

  init(localPermissions: PermissionManager.Snapshot) {
    self.source = .localSystem
    self.permissions = StatusPermissions(localPermissions)
    self.controllers = .unavailable
    self.compatibility = .unavailable
    self.output = .unavailable
    self.applicationServicePayload = nil
  }

  private init() {
    self.source = .unavailable
    self.permissions = .unavailable
    self.controllers = .unavailable
    self.compatibility = .unavailable
    self.output = .unavailable
    self.applicationServicePayload = nil
  }

  static let unavailable = Self()
}

enum RuntimeStatusSource: Sendable, Equatable {
  case runningApplication
  case localSystem
  case unavailable
}

enum RuntimeStatusText {
  static func permissionLines(_ permissions: StatusPermissions) -> [String] {
    [
      "Permissions:", "  Input Monitoring : \(permissionText(permissions.inputMonitoring))",
      "  Accessibility    : \(permissionText(permissions.accessibility))",
      "  Overall          : \(overallPermissionText(permissions))"
    ]
  }

  static func payloadLines(_ snapshot: RuntimeStatusSnapshot) -> [String] {
    var lines = ["(connected to running main app)", ""]
    lines.append(contentsOf: permissionLines(snapshot.permissions))
    lines.append("")
    lines.append("Compatibility output:")
    if let identity = snapshot.compatibility.identity {
      lines.append("  identity  : \(identity.rawValue)")
    } else {
      lines.append("  identity  : unavailable")
    }
    lines.append("  backend   : \(snapshot.output.state.rawValue)")
    if let diagnostic = snapshot.output.diagnostic {
      lines.append("  status    : error: \(diagnostic)")
    } else if let detail = snapshot.output.detail {
      lines.append("  status    : \(detail)")
    }
    lines.append("")
    lines.append(contentsOf: controllerLines(snapshot.controllers))
    return lines
  }

  static func directModeLines(_ permissions: StatusPermissions) -> [String] {
    var lines = ["(direct mode - app service not running)", ""]
    lines.append(contentsOf: permissionLines(permissions))
    lines.append("  -> App recovery: launch the installed OpenJoystickDriver app")
    return lines
  }

  private static func permissionText(_ state: StatusPermissionState) -> String {
    switch state {
    case .granted: return "[OK] granted"
    case .denied: return "[DENIED] denied"
    case .unknown: return "[UNKNOWN] unknown"
    case .unavailable: return "[UNAVAILABLE] unavailable"
    }
  }

  private static func overallPermissionText(_ permissions: StatusPermissions) -> String {
    if !permissions.isAvailable { return "[UNAVAILABLE] unavailable" }
    return permissions.isReady ? "[OK] ready" : "[ACTION] blocked"
  }

  private static func controllerLines(_ status: ConnectedControllersStatus) -> [String] {
    guard status.isAvailable else { return ["Devices: unavailable"] }
    guard !status.descriptions.isEmpty else { return ["Devices: (none connected)"] }

    var lines = ["Devices (\(status.descriptions.count)):"]
    for device in status.descriptions {
      let serialNumber = device.serialNumber ?? "none"
      lines.append(
        "  \(device.name) (VID:\(device.vendorID) PID:\(device.productID) "
          + "\(device.parser) [\(device.connection)] SN:\(serialNumber))"
      )
      let quirks =
        device.quirks.isEmpty ? "none" : device.quirks.joined(separator: ",")
      let backends =
        device.preferredBackends.isEmpty ? "none" : device.preferredBackends.joined(separator: ",")
      lines.append(
        "    protocol=\(device.protocolVariant.rawValue)"
          + " endpoints=in:0x\(String(device.inputEndpoint, radix: 16))"
          + " out:0x\(String(device.outputEndpoint, radix: 16))"
          + " setConfig=\(device.needsSetConfiguration)"
          + " settleMs=\(device.postHandshakeSettleMs)"
      )
      lines.append("    quirks=\(quirks) backends=\(backends)")
      let capabilities = device.physicalOutputCapabilities
      let motors = capabilities.rumbleMotors.map(\.rawValue)
      let lighting = capabilities.lightingFeatures.map(\.rawValue)
      let binaryMotors = capabilities.binaryRumbleMotors.map(\.rawValue)
      lines.append(
        "    physical-output motors=\(motors.isEmpty ? "none" : motors.joined(separator: ","))"
          + " lighting=\(lighting.isEmpty ? "none" : lighting.joined(separator: ","))"
          + " binary=\(binaryMotors.isEmpty ? "none" : binaryMotors.joined(separator: ","))"
      )
    }
    return lines
  }
}
