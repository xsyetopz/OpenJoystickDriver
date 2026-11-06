import Foundation

/// Builds, names and writes the support report.
package enum SupportReportService {
  /// Builds a ``SupportReport`` from the service's snapshots and the local build and system facts.
  ///
  /// `status` and `virtualDiagnostics` are nil when the service did not answer; the report then
  /// says so in its notes.
  package static func make(
    status: ApplicationServiceStatusPayload?,
    virtualDiagnostics: ApplicationServiceVirtualDeviceDiagnosticsPayload?,
    inputRead: PermissionManager.AccessState,
    applicationServiceHealth: ApplicationServiceManager.ApplicationServiceHealth?,
    applicationServiceInstalled: Bool,
    applicationServiceConnected: Bool,
    buildIdentity: BuildIdentity,
    systemGamepadAudit: SystemGamepadSupportAudit? = nil,
    frameTimings: [ControllerFrameTimings] = [],
    generatedAt: Date = Date()
  ) -> SupportReport {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    return SupportReport(
      generatedAt: generatedAt,
      buildIdentity: buildIdentity,
      osName: osName,
      osVersion: osVersion,
      architecture: architecture,
      inputRead: inputRead,
      applicationServiceInstalled: applicationServiceInstalled,
      applicationServiceConnected: applicationServiceConnected,
      applicationServiceHealth: applicationServiceHealth,
      systemGamepadAudit: systemGamepadAudit,
      frameTimings: frameTimings,
      status: status,
      virtualDiagnostics: virtualDiagnostics
    )
  }

  /// The name of a support report file for `date`, such as
  /// `OpenJoystickDriver-support-20260102-030405.json`, with the time in UTC.
  package static func defaultFilename(at date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return "OpenJoystickDriver-support-\(formatter.string(from: date)).json"
  }

  /// Writes `report` to `outputURL` atomically.
  ///
  /// - Throws: An `NSError` of code `NSFileWriteFileExistsError` when a file exists at `outputURL`
  ///   and `overwrite` is false, or the error of the encoding or the write.
  package static func write(
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
            "A file already exists at \(outputURL.path). Choose another output path."
        ]
      )
    }
    try report.encodedJSON().write(to: outputURL, options: .atomic)
  }

  /// The name of the operating system that OJD was built for.
  private static var osName: String {
    #if os(macOS)
      return "macOS"
    #elseif os(Linux)
      return "Linux"
    #elseif os(Windows)
      return "Windows"
    #else
      return "unknown"
    #endif
  }

  /// The processor architecture that OJD was built for.
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
