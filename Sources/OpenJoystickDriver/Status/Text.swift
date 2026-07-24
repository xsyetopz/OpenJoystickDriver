import OpenJoystickDriverKit

enum RuntimeStatusText {
  static func permissionLines(_ permissions: StatusPermissions) -> [String] {
    [
      "Permissions:", "  Input Monitoring : \(permissionText(permissions.inputMonitoring))",
      "  Accessibility    : \(permissionText(permissions.accessibility))",
      "  Overall          : \(overallPermissionText(permissions))",
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
      let mappings =
        device.mappingFlags.isEmpty ? "none" : device.mappingFlags.joined(separator: ",")
      let backends =
        device.preferredBackends.isEmpty ? "none" : device.preferredBackends.joined(separator: ",")
      lines.append(
        "    protocol=\(device.protocolVariant.rawValue)"
          + " endpoints=in:0x\(String(device.inputEndpoint, radix: 16))"
          + " out:0x\(String(device.outputEndpoint, radix: 16))"
          + " setConfig=\(device.needsSetConfiguration)"
          + " settleMs=\(device.postHandshakeSettleMs)"
      )
      lines.append("    mappings=\(mappings) backends=\(backends)")
      let capabilities = device.physicalOutputCapabilities
      let motors = capabilities.rumbleMotors.map(\.rawValue)
      let lighting = capabilities.lightingFeatures.map(\.rawValue)
      let binaryMotors = capabilities.binaryRumbleMotors.map(\.rawValue)
      lines.append(
        "    physical-output motors=\(motors.isEmpty ? "none" : motors.joined(separator: ","))"
          + " lighting=\(lighting.isEmpty ? "none" : lighting.joined(separator: ","))"
          + " binary=\(binaryMotors.isEmpty ? "none" : binaryMotors.joined(separator: ","))"
          + " evidence=\(capabilities.evidence.rawValue)"
      )
    }
    return lines
  }
}
