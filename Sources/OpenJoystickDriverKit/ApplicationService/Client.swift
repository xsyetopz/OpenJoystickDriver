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
  private let socketPath: String
  private var connected = false

  public init() { socketPath = LocalServiceRPCTransport.defaultSocketPath }

  init(socketPath: String) { self.socketPath = socketPath }

  /// Connects to the running main app, launching the installed app when needed.
  public func connect(timeoutSeconds: TimeInterval = 5) {
    if waitForLocalServer(until: Date()) { return }
    let timeout = max(0, timeoutSeconds)
    let deadline = Date().addingTimeInterval(timeout)
    switch Self.launchPolicy(
      commandLineArguments: CommandLine.arguments,
      bundlePathExtension: Bundle.main.bundleURL.pathExtension
    ) {
    case .waitForLocalServer:
      break
    case .spawnBundleExecutable:
      let grace = Date().addingTimeInterval(
        min(Self.concurrentHostLaunchGraceSeconds, timeout)
      )
      if waitForLocalServer(until: grace) { return }
      spawnMainApplicationExecutable()
    case .unavailable:
      break
    }
    if waitForLocalServer(until: deadline) { return }
    stateLock.withLock { connected = false }
  }

  public func disconnect() { stateLock.withLock { connected = false } }

  public var isConnected: Bool { stateLock.withLock { connected } }

  public func listDevices() async throws -> [String] {
    try await call("listDevices", LocalServiceRPCEmptyArguments())
  }

  public func getStatus() async throws -> ApplicationServiceStatusPayload {
    let data: Data = try await call("getStatus", LocalServiceRPCEmptyArguments())
    guard let payload = try? JSONDecoder().decode(ApplicationServiceStatusPayload.self, from: data)
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func requestRequiredAccess() async throws -> PermissionManager.Snapshot {
    try await call("requestRequiredAccess", LocalServiceRPCEmptyArguments())
  }

  public func requestAccess(_ requirement: PermissionManager.Requirement) async throws
    -> PermissionManager.Snapshot
  { try await call("requestAccess", LocalServiceRPCPermissionArguments(requirement: requirement)) }

  public func deviceInputState(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil
  ) async throws -> DeviceInputState? {
    let data: Data? = try await call(
      "getDeviceInputState",
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let data else { return nil }
    return try? JSONDecoder().decode(DeviceInputState.self, from: data)
  }

  public func packetLog(vendorID: UInt16, productID: UInt16, runtimeIdentifier: String? = nil)
    async throws -> [PacketLogEntry]
  {
    let data: Data = try await call(
      "getPacketLog",
      LocalServiceRPCDeviceArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier
      )
    )
    guard let entries = try? JSONDecoder().decode([PacketLogEntry].self, from: data) else {
      throw ApplicationServiceClientError.invalidResponse
    }
    return entries
  }

  public func sendPhysicalRumble(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
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
        runtimeIdentifier: runtimeIdentifier,
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
    runtimeIdentifier: String? = nil,
    indicator: PhysicalPlayerIndicator
  ) async throws -> Bool {
    try await call(
      "setPhysicalPlayerIndicator",
      LocalServiceRPCPlayerIndicatorArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        playerIndex: indicator.rawValue
      )
    )
  }

  public func setPhysicalColor(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
    red: UInt8,
    green: UInt8,
    blue: UInt8
  ) async throws -> Bool {
    try await call(
      "setPhysicalColor",
      LocalServiceRPCColorArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        red: Int(red),
        green: Int(green),
        blue: Int(blue)
      )
    )
  }

  public func setPhysicalBrightness(
    vendorID: UInt16,
    productID: UInt16,
    runtimeIdentifier: String? = nil,
    brightness: UInt8
  ) async throws -> Bool {
    try await call(
      "setPhysicalBrightness",
      LocalServiceRPCBrightnessArguments(
        vendorID: Int(vendorID),
        productID: Int(productID),
        runtimeIdentifier: runtimeIdentifier,
        brightness: Int(brightness)
      )
    )
  }

  public func setSuppressOutput(_ suppress: Bool) async throws {
    let _: Bool = try await call("setSuppressOutput", LocalServiceRPCBoolArguments(value: suppress))
  }

  public func getVirtualDeviceDiagnostics() async throws
    -> ApplicationServiceVirtualDeviceDiagnosticsPayload
  {
    let data: Data = try await call("getVirtualDeviceDiagnostics", LocalServiceRPCEmptyArguments())
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceDiagnosticsPayload.self,
        from: data
      )
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func setCompatibilityIdentity(_ raw: String) async throws -> Bool {
    try await call("setCompatibilityIdentity", LocalServiceRPCStringArguments(value: raw))
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
      timeoutSeconds: TimeInterval(clampedSeconds) + applicationServiceSelfTestReplyGraceSeconds
    )
    guard
      let payload = try? JSONDecoder().decode(
        ApplicationServiceVirtualDeviceSelfTestPayload.self,
        from: data
      )
    else { throw ApplicationServiceClientError.invalidResponse }
    return payload
  }

  public func resetSettings() async throws -> Bool {
    try await call("resetSettings", LocalServiceRPCEmptyArguments())
  }

  public func getRemappingSnapshot() async throws -> ApplicationServiceRemappingSnapshotPayload {
    try await remappingCall(.getSnapshot, LocalServiceRPCEmptyArguments())
  }

  public func getRemappingProfile(id: UUID) async throws -> RemappingProfile {
    try await remappingCall(
      .getProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  public func createRemappingProfile(_ profile: RemappingProfile) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .createProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  public func updateRemappingProfile(_ profile: RemappingProfile, expectedCurrent: RemappingProfile)
    async throws -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .updateProfile,
      ApplicationServiceRemappingProfileUpdateArguments(
        profile: profile,
        expectedCurrent: expectedCurrent
      )
    )
  }

  public func importRemappingProfile(_ profile: RemappingProfile) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .importProfile,
      ApplicationServiceRemappingProfileArguments(profile: profile)
    )
  }

  public func deleteRemappingProfile(id: UUID) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .deleteProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  public func activateRemappingProfile(id: UUID) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .activateProfile,
      ApplicationServiceRemappingProfileIDArguments(profileID: id)
    )
  }

  public func deactivateRemappingProfile(vendorID: UInt16, productID: UInt16) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .deactivateProfile,
      ApplicationServiceRemappingModelArguments(vendorID: vendorID, productID: productID)
    )
  }

  public func deactivateRemappingProfile(profileID: UUID) async throws
    -> ApplicationServiceRemappingSnapshotPayload
  {
    try await remappingCall(
      .deactivateProfileByID,
      ApplicationServiceRemappingProfileIDArguments(profileID: profileID)
    )
  }

  public func getRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingCall(.getPostEventAccess, LocalServiceRPCEmptyArguments())
  }

  public func requestRemappingPostEventAccess() async throws -> RemappingPostEventAccessState {
    try await remappingCall(.requestPostEventAccess, LocalServiceRPCEmptyArguments())
  }

  private func remappingCall<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
    _ method: ApplicationServiceRemappingRPCMethod,
    _ arguments: Arguments
  ) async throws -> Value {
    do { return try await call(method.rawValue, arguments) } catch LocalServiceRPCError.remote(
      let description
    ) {
      guard let error = ApplicationServiceRemappingRPCError(rpcDescription: description) else {
        throw LocalServiceRPCError.remote(description)
      }
      throw error
    }
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
        timeoutSeconds: timeoutSeconds,
        socketPath: socketPath
      )
    } catch LocalServiceRPCError.timeout { throw ApplicationServiceClientError.timeout }
  }

  private func waitForLocalServer(until deadline: Date) -> Bool {
    while true {
      if LocalServiceRPCClient.serverProcessIdentifier(socketPath: socketPath) != nil {
        stateLock.withLock { connected = true }
        return true
      }
      if Date() >= deadline { return false }
      Thread.sleep(forTimeInterval: 0.1)
    }
  }

  private func spawnMainApplicationExecutable() {
    guard let executable = Bundle.main.executableURL else { return }
    let process = Process()
    process.executableURL = executable
    process.arguments = []
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch {
      FileHandle.standardError.write(
        Data(
          "[ApplicationServiceClient] Could not launch main app: ".appending(
            "\(error.localizedDescription)\n"
          ).utf8
        )
      )
    }
  }
}

extension ApplicationServiceClient {
  enum LaunchPolicy: Equatable, Sendable {
    case waitForLocalServer
    case spawnBundleExecutable
    case unavailable
  }

  static let concurrentHostLaunchGraceSeconds: TimeInterval = 0.5

  static func launchPolicy(
    commandLineArguments: [String],
    bundlePathExtension: String
  ) -> LaunchPolicy {
    guard bundlePathExtension == "app" else { return .unavailable }
    if commandLineArguments.dropFirst().isEmpty { return .waitForLocalServer }
    return .spawnBundleExecutable
  }
}
