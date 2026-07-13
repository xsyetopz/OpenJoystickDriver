import Foundation
import OpenJoystickDriverKit

enum SupportReportService {
  static func make(
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    inputMonitoring: PermissionManager.AccessState,
    applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth?,
    applicationServiceInstalled: Bool,
    applicationServiceConnected: Bool,
    appVersion: String,
    appleGameControllerAudit: AppleGameControllerSupportAudit? = nil,
    generatedAt: Date = Date()
  ) -> SupportReport {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    return SupportReport(
      generatedAt: generatedAt,
      appVersion: appVersion,
      macOSVersion: macOSVersion,
      architecture: architecture,
      inputMonitoring: inputMonitoring,
      applicationServiceInstalled: applicationServiceInstalled,
      applicationServiceConnected: applicationServiceConnected,
      applicationServiceHealth: applicationServiceHealth,
      appleGameControllerAudit: appleGameControllerAudit,
      status: status,
      virtualDiagnostics: virtualDiagnostics
    )
  }

  static func defaultFilename(at date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "OpenJoystickDriver-support-\(formatter.string(from: date)).json"
  }

  static func write(
    _ report: SupportReport,
    to outputURL: URL,
    overwrite: Bool = false
  ) throws {
    if !overwrite && FileManager.default.fileExists(atPath: outputURL.path) {
      throw NSError(
        domain: "OpenJoystickDriver.SupportReport",
        code: NSFileWriteFileExistsError,
        userInfo: [
          NSLocalizedDescriptionKey:
            "A file already exists at \(outputURL.path). Choose another output path.",
        ]
      )
    }
    try report.encodedJSON().write(to: outputURL, options: .atomic)
  }

  private static var architecture: String {
    #if arch(arm64)
      return "arm64"
    #elseif arch(x86_64)
      return "x86_64"
    #else
      return "unknown"
    #endif
  }
}
