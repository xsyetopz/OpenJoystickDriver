import Foundation
import OpenJoystickDriverKit

enum BrowserGamepadTarget: String, CaseIterable, Sendable {
  case none
  case systemDefault = "default"
  case safari
  case chrome
  case firefox
  case all

  var displayName: String {
    switch self {
    case .none: "Do not open"
    case .systemDefault: "Default browser"
    case .safari: "Safari"
    case .chrome: "Google Chrome"
    case .firefox: "Firefox"
    case .all: "Safari + Chrome + Firefox"
    }
  }
}

final class BrowserGamepadDiagnosticSession: @unchecked Sendable {
  let id = UUID()
  let url: URL
  private let server: BrowserGamepadLocalServer

  init(url: URL, server: BrowserGamepadLocalServer) {
    self.url = url
    self.server = server
  }

  var snapshotCount: Int { server.snapshotCount }

  func encodedSnapshots() throws -> Data {
    try server.encodedSnapshots()
  }

  func stop() {
    server.stop()
  }

  deinit {
    stop()
  }
}

enum BrowserGamepadDiagnosticService {
  static func start(port: Int) throws -> BrowserGamepadDiagnosticSession {
    guard (1...65_535).contains(port), let serverPort = UInt16(exactly: port) else {
      throw error("Port must be 1...65535.")
    }
    guard let pageURL = Bundle.module.url(
      forResource: "browser-gamepad",
      withExtension: "html",
      subdirectory: "Resources/Diagnostics"
    ) else {
      throw error("Bundled browser diagnostic page is missing.")
    }
    guard
      let diagnosticURL = URL(
        string: "http://127.0.0.1:\(port)/\(pageURL.lastPathComponent)"
      )
    else {
      throw error("Could not construct the local diagnostic URL.")
    }

    let page = try Data(contentsOf: pageURL)
    let server = try BrowserGamepadLocalServer(page: page, port: serverPort)
    server.start()
    return BrowserGamepadDiagnosticSession(url: diagnosticURL, server: server)
  }

  static func open(_ url: URL, target: BrowserGamepadTarget) -> [String] {
    let applications: [String?]
    switch target {
    case .none: return []
    case .systemDefault: applications = [nil]
    case .safari: applications = ["Safari"]
    case .chrome: applications = ["Google Chrome"]
    case .firefox: applications = ["Firefox"]
    case .all: applications = ["Safari", "Google Chrome", "Firefox"]
    }

    return applications.compactMap { application in
      let arguments =
        application.map { ["-a", $0, url.absoluteString] }
        ?? [url.absoluteString]
      do {
        let result = try BoundedProcessRunner.run(
          executableURL: URL(fileURLWithPath: "/usr/bin/open"),
          arguments: arguments,
          timeoutSeconds: 5,
          maximumOutputBytes: 65_536
        )
        if result.timedOut {
          return "Opening \(application ?? "default browser") timed out."
        }
        guard result.terminationStatus == 0 else {
          let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
          return detail.isEmpty
            ? "Could not open \(application ?? "default browser")."
            : "Could not open \(application ?? "default browser"): \(detail)"
        }
        return nil
      } catch {
        return "Could not open \(application ?? "default browser"): "
          + error.localizedDescription
      }
    }
  }

  static func openAsync(_ url: URL, target: BrowserGamepadTarget) async -> [String] {
    await Task.detached(priority: .userInitiated) {
      open(url, target: target)
    }.value
  }

  private static func error(_ description: String) -> NSError {
    NSError(
      domain: "OpenJoystickDriver.BrowserGamepadDiagnostic",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: description]
    )
  }
}
