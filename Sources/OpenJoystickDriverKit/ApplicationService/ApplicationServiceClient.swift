import AppKit
import Foundation

let applicationServiceDefaultReplyTimeoutSeconds: TimeInterval = 5
let applicationServiceSelfTestReplyGraceSeconds: TimeInterval = 5

public enum ApplicationServiceClientError: Error, LocalizedError, Sendable {
  case notConnected
  case timeout
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .notConnected: return "Not connected to main application."
    case .timeout: return "Main application did not respond before the deadline."
    case .invalidResponse: return "Main application returned an invalid response."
    }
  }
}

public final class ApplicationServiceClient: @unchecked Sendable {
  private let stateLock = NSLock()
  private var connected = false

  public init() {}

  /// Connects to the running main app, launching the installed app when needed.
  public func connect() {
    if LocalServiceRPCClient.isAvailable() {
      stateLock.withLock { connected = true }
      return
    }
    launchMainApplicationIfPossible()
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      if LocalServiceRPCClient.isAvailable() {
        stateLock.withLock { connected = true }
        return
      }
      Thread.sleep(forTimeInterval: 0.1)
    }
    stateLock.withLock { connected = false }
  }

  public func disconnect() {
    stateLock.withLock { connected = false }
  }

  public var isConnected: Bool {
    stateLock.withLock { connected }
  }

  public func listDevices() async throws -> [String] {
    try await call("listDevices", LocalServiceRPCEmptyArguments())
  }

  public func getStatus() async throws -> ApplicationServiceStatusPayload {
    let data: Data = try await call("getStatus", LocalServiceRPCEmptyArguments())
    guard
      let payload = try? JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return payload
  }

  public func requestRequiredAccess() async throws -> PermissionManager.Snapshot {
    try await call("requestRequiredAccess", LocalServiceRPCEmptyArguments())
  }

  public func deviceInputState(vendorID: UInt16, productID: UInt16) async throws
    -> DeviceInputState?
  {
    let data: Data? = try await call(
      "getDeviceInputState",
      LocalServiceRPCDeviceArguments(vendorID: Int(vendorID), productID: Int(productID))
    )
    guard let data else { return nil }
    return try? JSONDecoder().decode(DeviceInputState.self, from: data)
  }

  public func packetLog(vendorID: UInt16, productID: UInt16) async throws -> [PacketLogEntry] {
    let data: Data = try await call(
      "getPacketLog",
      LocalServiceRPCDeviceArguments(vendorID: Int(vendorID), productID: Int(productID))
    )
    guard let entries = try? JSONDecoder().decode([PacketLogEntry].self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return entries
  }

  public func sendPhysicalRumble(
    vendorID: UInt16,
    productID: UInt16,
    left: UInt8,
    right: UInt8,
    lt: UInt8,
    rt: UInt8,
    durationMs: Int
  ) async throws -> Bool {
    try await call(
      "sendPhysicalRumble",
      LocalServiceRPCRumbleArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        left: Int(left),
        right: Int(right),
        leftTrigger: Int(lt),
        rightTrigger: Int(rt),
        durationMilliseconds: durationMs
      )
    )
  }

  public func setPhysicalPlayerIndicator(
    vendorID: UInt16,
    productID: UInt16,
    indicator: PhysicalPlayerIndicator
  ) async throws -> Bool {
    try await call(
      "setPhysicalPlayerIndicator",
      LocalServiceRPCPlayerIndicatorArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        playerIndex: indicator.rawValue
      )
    )
  }

  public func setPhysicalColor(
    vendorID: UInt16,
    productID: UInt16,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    try await call(
      "setPhysicalColor",
      LocalServiceRPCColorArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        red: Int(red),
        green: Int(green),
        blue: Int(blue)
      )
    )
  }

  public func setPhysicalBrightness(
    vendorID: UInt16,
    productID: UInt16,
    brightness: UInt8
  ) async throws -> Bool {
    try await call(
      "setPhysicalBrightness",
      LocalServiceRPCBrightnessArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        brightness: Int(brightness)
      )
    )
  }

  public func setSuppressOutput(_ suppress: Bool) async throws {
    let _: Bool = try await call(
      "setSuppressOutput",
      LocalServiceRPCBoolArguments(value: suppress)
    )
  }

  public func getVirtualDeviceDiagnostics() async throws
    -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    let data: Data = try await call(
      "getVirtualDeviceDiagnostics",
      LocalServiceRPCEmptyArguments()
    )
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceDiagnosticsPayload.self,
        from: data
      )
    else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return payload
  }

  public func setCompatibilityIdentity(_ raw: String) async throws {
    let _: Bool = try await call(
      "setCompatibilityIdentity",
      LocalServiceRPCStringArguments(value: raw)
    )
  }

  public func getCompatibilityIdentity() async throws -> String {
    try await call("getCompatibilityIdentity", LocalServiceRPCEmptyArguments())
  }

  public func runVirtualDeviceSelfTest(seconds: Int) async throws
    -> ApplicationServiceVirtualDeviceSelfTestPayload
  {
    let clampedSeconds = max(1, min(30, seconds))
    let data: Data = try await call(
      "runVirtualDeviceSelfTest",
      LocalServiceRPCIntArguments(value: clampedSeconds),
      timeoutSeconds:
        TimeInterval(clampedSeconds) + applicationServiceSelfTestReplyGraceSeconds
    )
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceSelfTestPayload.self,
        from: data
      )
    else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return payload
  }

  public func resetSettings() async throws -> Bool {
    try await call("resetSettings", LocalServiceRPCEmptyArguments())
  }

  private func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    _ method: String,
    _ arguments: Arguments,
    timeoutSeconds: TimeInterval = applicationServiceDefaultReplyTimeoutSeconds
  ) async throws -> Value {
    guard stateLock.withLock({ connected }) else {
      throw ApplicationServiceClientError.notConnected
    }
    do {
      return try await LocalServiceRPCClient.call(
        method: method,
        arguments: arguments,
        timeoutSeconds: timeoutSeconds
      )
    } catch LocalServiceRPCError.timeout {
      throw ApplicationServiceClientError.timeout
    }
  }

  private func launchMainApplicationIfPossible() {
    guard Bundle.main.bundleURL.pathExtension == "app" else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL,
      configuration: configuration
    ) { _, error in
      if let error {
        FileHandle.standardError.write(
          Data(
            "[ApplicationServiceClient] Could not launch main app: "
              .appending("\(error.localizedDescription)\n").utf8
          )
        )
      }
    }
  }
}
